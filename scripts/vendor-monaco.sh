#!/usr/bin/env bash
set -euo pipefail
# Vendors monaco-editor's min/vs build into Resources/monaco/vs.
# Re-run to bump the version (edit MONACO_VERSION).
MONACO_VERSION="0.55.1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/monaco"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
npm pack "monaco-editor@${MONACO_VERSION}" >/dev/null
tar -xzf "monaco-editor-${MONACO_VERSION}.tgz"
rm -rf "$DEST/vs"
mkdir -p "$DEST"
cp -R "package/min/vs" "$DEST/vs"
echo "$MONACO_VERSION" > "$DEST/VERSION"
echo "Vendored monaco-editor ${MONACO_VERSION} -> $DEST/vs"
