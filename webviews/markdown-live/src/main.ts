// Obsidian-style live-preview markdown editor for cmux markdown panels.
//
// The document stays plain markdown (lossless round-trip, safe alongside agents
// editing the same file). Formatting renders in place; the raw syntax (`#`,
// `**`, `[]()`, `>`, list bullets, task brackets, code fences) reappears only on
// the lines the cursor touches.
//
// Speaks the same Swift bridge as `monaco.html` (`window.cmuxMonaco` +
// `cmuxMonacoBridge` messages), so `MonacoWebController` drives it unchanged.

import { EditorSelection, EditorState, type Extension, type Range, Transaction } from "@codemirror/state";
import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
  WidgetType,
  drawSelection,
  keymap,
} from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { markdown, markdownKeymap, markdownLanguage } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting, syntaxTree } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";

type BridgeMessage =
  | { type: "ready" | "editing" | "focus" | "blur" }
  | { type: "change" | "requestSave"; content: string };

function post(msg: BridgeMessage): void {
  try {
    (window as any).webkit.messageHandlers.cmuxMonacoBridge.postMessage(msg);
  } catch {
    // Not hosted in cmux (e.g. opened in a browser for debugging).
  }
}

// MARK: - Widgets

class BulletWidget extends WidgetType {
  eq(): boolean {
    return true;
  }
  toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-lp-bullet";
    span.textContent = "•";
    return span;
  }
}

class CheckboxWidget extends WidgetType {
  constructor(readonly checked: boolean, readonly pos: number) {
    super();
  }
  eq(other: CheckboxWidget): boolean {
    return other.checked === this.checked && other.pos === this.pos;
  }
  toDOM(view: EditorView): HTMLElement {
    const box = document.createElement("input");
    box.type = "checkbox";
    box.className = "cm-lp-checkbox";
    box.checked = this.checked;
    box.addEventListener("mousedown", (event) => {
      event.preventDefault();
      // `pos` is the `[` of `[ ]` / `[x]`; flip the character inside.
      view.dispatch({
        changes: { from: this.pos + 1, to: this.pos + 2, insert: this.checked ? " " : "x" },
      });
    });
    return box;
  }
  ignoreEvent(): boolean {
    return false;
  }
}

class RuleWidget extends WidgetType {
  eq(): boolean {
    return true;
  }
  toDOM(): HTMLElement {
    const hr = document.createElement("span");
    hr.className = "cm-lp-hr";
    return hr;
  }
}

class FenceLabelWidget extends WidgetType {
  constructor(readonly label: string) {
    super();
  }
  eq(other: FenceLabelWidget): boolean {
    return other.label === this.label;
  }
  toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-lp-fence-label";
    span.textContent = this.label;
    return span;
  }
}

// MARK: - Live preview decorations

const hidden = Decoration.replace({});
const lineClass = (cls: string) => Decoration.line({ class: cls });
const markClass = (cls: string) => Decoration.mark({ class: cls });

/// Line numbers (1-based) that any selection range touches.
function activeLines(state: EditorState): Set<number> {
  const lines = new Set<number>();
  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;
    for (let n = first; n <= last; n++) lines.add(n);
  }
  return lines;
}

function buildDecorations(view: EditorView): DecorationSet {
  const { state } = view;
  const doc = state.doc;
  const active = view.hasFocus ? activeLines(state) : new Set<number>();
  const decos: Range<Decoration>[] = [];

  const lineOf = (pos: number) => doc.lineAt(pos).number;
  const isActive = (from: number, to: number) => {
    const first = lineOf(from);
    const last = lineOf(Math.max(from, to - 1));
    for (let n = first; n <= last; n++) if (active.has(n)) return true;
    return false;
  };
  const eachLine = (from: number, to: number, fn: (lineFrom: number) => void) => {
    let pos = from;
    while (pos <= to) {
      const line = doc.lineAt(pos);
      fn(line.from);
      if (line.to >= to) break;
      pos = line.to + 1;
    }
  };
  /// Hides `[from, to)` plus one trailing space when present (e.g. `# `, `> `).
  const hideWithSpace = (from: number, to: number) => {
    const end = doc.sliceString(to, to + 1) === " " ? to + 1 : to;
    if (end > from) decos.push(hidden.range(from, end));
  };

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter: (node) => {
        const name = node.name;

        const heading = /^ATXHeading(\d)$/.exec(name);
        if (heading) {
          decos.push(lineClass(`cm-lp-h cm-lp-h${heading[1]}`).range(doc.lineAt(node.from).from));
          return;
        }

        switch (name) {
          case "HeaderMark": {
            const parent = node.node.parent;
            if (parent && /^ATXHeading/.test(parent.name) && !isActive(node.from, node.to)) {
              hideWithSpace(node.from, node.to);
            }
            return;
          }
          case "Emphasis":
            decos.push(markClass("cm-lp-em").range(node.from, node.to));
            return;
          case "StrongEmphasis":
            decos.push(markClass("cm-lp-strong").range(node.from, node.to));
            return;
          case "Strikethrough":
            decos.push(markClass("cm-lp-strike").range(node.from, node.to));
            return;
          case "InlineCode":
            decos.push(markClass("cm-lp-code").range(node.from, node.to));
            return;
          case "EmphasisMark":
          case "StrikethroughMark":
            if (!isActive(node.from, node.to)) decos.push(hidden.range(node.from, node.to));
            return;
          case "CodeMark": {
            // Inline code backticks only; fenced-code marks are handled by FencedCode.
            const parent = node.node.parent;
            if (parent?.name === "InlineCode" && !isActive(node.from, node.to)) {
              decos.push(hidden.range(node.from, node.to));
            }
            return;
          }
          case "Link": {
            const marks = node.node.getChildren("LinkMark");
            if (marks.length >= 2) {
              const labelFrom = marks[0].to;
              const labelTo = marks[1].from;
              if (labelTo > labelFrom) {
                decos.push(markClass("cm-lp-link").range(labelFrom, labelTo));
              }
              if (!isActive(node.from, node.to) && labelTo > labelFrom) {
                decos.push(hidden.range(node.from, labelFrom));
                decos.push(hidden.range(labelTo, node.to));
              }
            }
            return false;
          }
          case "URL":
            if (node.node.parent?.name !== "Link") {
              decos.push(markClass("cm-lp-link").range(node.from, node.to));
            }
            return;
          case "Blockquote":
            eachLine(node.from, node.to, (lineFrom) => decos.push(lineClass("cm-lp-quote").range(lineFrom)));
            return;
          case "QuoteMark":
            if (!isActive(node.from, node.to)) hideWithSpace(node.from, node.to);
            return;
          case "ListMark": {
            const list = node.node.parent?.parent;
            if (list?.name === "BulletList") {
              const item = node.node.parent;
              const hasTask = item?.getChild("Task") != null;
              if (!isActive(node.from, node.to)) {
                if (hasTask) {
                  hideWithSpace(node.from, node.to);
                } else {
                  decos.push(Decoration.replace({ widget: new BulletWidget() }).range(node.from, node.to));
                }
              }
            } else {
              decos.push(markClass("cm-lp-ordinal").range(node.from, node.to));
            }
            return;
          }
          case "TaskMarker":
            if (!isActive(node.from, node.to)) {
              const checked = /x/i.test(doc.sliceString(node.from, node.to));
              decos.push(
                Decoration.replace({ widget: new CheckboxWidget(checked, node.from) }).range(node.from, node.to),
              );
              if (checked) {
                const line = doc.lineAt(node.from);
                if (node.to < line.to) decos.push(markClass("cm-lp-done").range(node.to, line.to));
              }
            }
            return;
          case "HorizontalRule":
            if (!isActive(node.from, node.to)) {
              decos.push(Decoration.replace({ widget: new RuleWidget() }).range(node.from, node.to));
            }
            return;
          case "FencedCode": {
            const blockActive = isActive(node.from, node.to);
            eachLine(node.from, node.to, (lineFrom) => decos.push(lineClass("cm-lp-codeblock").range(lineFrom)));
            const first = doc.lineAt(node.from);
            const last = doc.lineAt(node.to);
            decos.push(lineClass("cm-lp-codeblock-first").range(first.from));
            decos.push(lineClass("cm-lp-codeblock-last").range(last.from));
            if (!blockActive) {
              const info = node.node.getChild("CodeInfo");
              const label = info ? doc.sliceString(info.from, info.to) : "";
              if (first.to > first.from) {
                decos.push(Decoration.replace({ widget: new FenceLabelWidget(label) }).range(first.from, first.to));
              }
              if (last.number !== first.number && /^\s*(```|~~~)/.test(last.text) && last.to > last.from) {
                decos.push(hidden.range(last.from, last.to));
              }
            }
            return false;
          }
          case "Table":
            eachLine(node.from, node.to, (lineFrom) => decos.push(lineClass("cm-lp-table").range(lineFrom)));
            return false;
          default:
            return;
        }
      },
    });
  }

  return Decoration.set(decos, true);
}

const livePreview = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = buildDecorations(view);
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.selectionSet || update.viewportChanged || update.focusChanged) {
        this.decorations = buildDecorations(update.view);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

// MARK: - Formatting commands

/// Wraps the selection in `marker` (or unwraps it when already wrapped).
function toggleWrap(marker: string) {
  return (view: EditorView): boolean => {
    const { state } = view;
    view.dispatch(
      state.changeByRange((range) => {
        const before = state.sliceDoc(range.from - marker.length, range.from);
        const after = state.sliceDoc(range.to, range.to + marker.length);
        if (before === marker && after === marker) {
          return {
            changes: [
              { from: range.from - marker.length, to: range.from },
              { from: range.to, to: range.to + marker.length },
            ],
            range: EditorSelection.range(range.from - marker.length, range.to - marker.length),
          };
        }
        return {
          changes: [
            { from: range.from, insert: marker },
            { from: range.to, insert: marker },
          ],
          range: EditorSelection.range(range.from + marker.length, range.to + marker.length),
        };
      }),
    );
    return true;
  };
}


// MARK: - Theme

const highlight = HighlightStyle.define([
  { tag: t.heading, fontWeight: "650" },
  { tag: t.strong, fontWeight: "650" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
  { tag: t.link, color: "var(--lp-link)" },
  { tag: t.url, color: "var(--lp-link)" },
  { tag: t.monospace, fontFamily: "var(--lp-mono)" },
  { tag: t.processingInstruction, color: "var(--lp-syntax)" },
  { tag: t.contentSeparator, color: "var(--lp-syntax)" },
  { tag: t.quote, color: "var(--lp-quote)" },
]);

const editorTheme = EditorView.theme({
  "&": { height: "100%", backgroundColor: "transparent", color: "var(--lp-fg)" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": {
    fontFamily: "var(--lp-font)",
    fontSize: "15px",
    lineHeight: "1.65",
    overflow: "auto",
  },
  ".cm-content": {
    maxWidth: "760px",
    margin: "0 auto",
    padding: "28px 36px 40vh",
    caretColor: "var(--lp-caret)",
  },
  ".cm-line": { padding: "0" },
  ".cm-cursor": { borderLeftColor: "var(--lp-caret)", borderLeftWidth: "2px" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {
    backgroundColor: "var(--lp-selection) !important",
  },
});

// MARK: - Editor

const SAVE_DEBOUNCE_MS = 600;
let saveTimer: ReturnType<typeof setTimeout> | null = null;
let editingPending = false;
let suppressChange = false;

function scheduleSave(view: EditorView): void {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    saveTimer = null;
    editingPending = false;
    post({ type: "change", content: view.state.doc.toString() });
  }, SAVE_DEBOUNCE_MS);
}

function requestSave(view: EditorView): boolean {
  if (saveTimer) {
    clearTimeout(saveTimer);
    saveTimer = null;
  }
  editingPending = false;
  post({ type: "requestSave", content: view.state.doc.toString() });
  return true;
}

function extensions(): Extension[] {
  return [
    history(),
    drawSelection(),
    EditorView.lineWrapping,
    markdown({ base: markdownLanguage }),
    syntaxHighlighting(highlight),
    livePreview,
    editorTheme,
    keymap.of([
      { key: "Mod-s", run: requestSave, preventDefault: true },
      { key: "Mod-b", run: toggleWrap("**") },
      { key: "Mod-i", run: toggleWrap("*") },
      { key: "Mod-e", run: toggleWrap("`") },
      ...markdownKeymap,
      indentWithTab,
      ...historyKeymap,
      ...defaultKeymap,
    ]),
    EditorView.updateListener.of((update) => {
      if (!update.docChanged || suppressChange) return;
      if (!editingPending) {
        editingPending = true;
        post({ type: "editing" });
      }
      scheduleSave(update.view);
    }),
    EditorView.domEventHandlers({
      focus: () => post({ type: "focus" }),
      blur: () => post({ type: "blur" }),
    }),
  ];
}

const view = new EditorView({
  state: EditorState.create({ doc: "", extensions: extensions() }),
  parent: document.getElementById("container")!,
});

function setTheme(theme: string): void {
  document.documentElement.dataset.theme = theme === "cmux-light" ? "light" : "dark";
}

function replaceDocument(text: string, keepSelection: boolean): void {
  suppressChange = true;
  try {
    if (keepSelection) {
      const head = Math.min(view.state.selection.main.head, text.length);
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: text },
        selection: { anchor: head },
        annotations: Transaction.addToHistory.of(false),
      });
    } else {
      view.setState(EditorState.create({ doc: text, extensions: extensions() }));
    }
  } finally {
    suppressChange = false;
  }
}

(window as any).cmuxMonaco = {
  setContent(text: string, _language: string, theme: string) {
    if (theme) setTheme(theme);
    replaceDocument(text, false);
  },
  applyExternalChange(text: string) {
    if (text === view.state.doc.toString()) return;
    replaceDocument(text, true);
  },
  setTheme,
  focus() {
    view.focus();
  },
  currentValue() {
    return view.state.doc.toString();
  },
  flushSave() {
    requestSave(view);
  },
  // Diff mode is a Monaco-only feature; the live editor never receives it.
  setDiff() {},
};

post({ type: "ready" });
