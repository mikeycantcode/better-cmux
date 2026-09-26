"use client";

import { useEffect, useRef } from "react";
import { useTranslations } from "next-intl";
import { DOWNLOAD_URL, DOWNLOAD_INTENT_PARAM } from "../../lib/download";
import { OfficialLinks } from "./official-links";

function triggerDownload() {
  const anchor = document.createElement("a");
  anchor.href = DOWNLOAD_URL;
  // `download` is ignored for cross-origin URLs, but the GitHub release asset
  // is served with Content-Disposition: attachment, so the click downloads the
  // file without navigating away from this page.
  anchor.download = "";
  anchor.rel = "noopener";
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
}

export function DownloadConfirmation() {
  const t = useTranslations("download");
  // Guard against React StrictMode's double-invoke (and any re-render) so the
  // download fires at most once per mount.
  const hasTriggered = useRef(false);

  useEffect(() => {
    if (hasTriggered.current) return;
    hasTriggered.current = true;
    // Auto-download only when the navigation carried the intent marker (set by
    // the Download CTAs). Reading the URL works for client-side `Link`
    // transitions, unlike the Performance navigation type which keeps the
    // original document's load type. Strip the marker afterwards so refreshing
    // or navigating back to this page does not re-trigger the download.
    const params = new URLSearchParams(window.location.search);
    if (params.get(DOWNLOAD_INTENT_PARAM) === "1") {
      triggerDownload();
      params.delete(DOWNLOAD_INTENT_PARAM);
      const query = params.toString();
      const cleanUrl =
        window.location.pathname +
        (query ? `?${query}` : "") +
        window.location.hash;
      window.history.replaceState(window.history.state, "", cleanUrl);
    }
  }, []);

  return (
    <main className="mx-auto w-full max-w-6xl px-6 py-16 sm:py-20">
      {/* Hero */}
      <div className="flex flex-col items-center text-center">
        {/* Inline SVG mark, not next/image (or even a plain <img> of
            /logo.png), on purpose: routing /logo.png through the image
            optimizer broke this hero in Safari (issue #5819), and rendering
            the brand tile as inline SVG sidesteps the optimizer entirely —
            there is no fetched image URL to cache. Decorative: the heading
            below already names the product. */}
        <svg
          width={60}
          height={60}
          viewBox="0 0 1024 1024"
          aria-hidden="true"
          focusable="false"
        >
          <style>{`
            .dc-stripe {
              animation: dc-stripe-in 600ms cubic-bezier(0.22, 1, 0.36, 1) both;
            }
            .dc-stripe-1 { animation-delay: 90ms; }
            .dc-stripe-2 { animation-delay: 180ms; }
            @keyframes dc-stripe-in {
              from { transform: translateY(6%); opacity: 0; }
              to { transform: translateY(0); opacity: 1; }
            }
            .dc-sheen {
              /* backwards: hold the off-tile start position during the 900ms
                 delay instead of flashing the band across the tile center. */
              animation: dc-sheen-sweep 3.5s ease-in-out 900ms infinite backwards;
            }
            @keyframes dc-sheen-sweep {
              0% { transform: translateX(-520px); }
              40% { transform: translateX(1520px); }
              100% { transform: translateX(1520px); }
            }
            @media (prefers-reduced-motion: reduce) {
              .dc-stripe { animation: none; }
              .dc-sheen { animation: none; visibility: hidden; }
            }
          `}</style>
          <defs>
            <linearGradient id="dc-bg" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#1B1B1F" />
              <stop offset="1" stopColor="#101014" />
            </linearGradient>
            <linearGradient id="dc-sheen-fade" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0" stopColor="#fff" stopOpacity="0" />
              <stop offset="0.5" stopColor="#fff" stopOpacity="1" />
              <stop offset="1" stopColor="#fff" stopOpacity="0" />
            </linearGradient>
            <clipPath id="dc-tile">
              <rect x="0" y="0" width="1024" height="1024" rx="229" />
            </clipPath>
          </defs>
          <rect x="0" y="0" width="1024" height="1024" rx="229" fill="url(#dc-bg)" />
          <g stroke="#fff" strokeWidth="88" strokeLinecap="round">
            {/* Stripes lean 18° clockwise from vertical (like ///): half-length
                310 → dx = 310·sin18° ≈ 95.8, dy = 310·cos18° ≈ 294.8. */}
            <line className="dc-stripe" x1="224.2" y1="806.8" x2="415.8" y2="217.2" />
            <line className="dc-stripe dc-stripe-1" x1="416.2" y1="806.8" x2="607.8" y2="217.2" />
            <line className="dc-stripe dc-stripe-2" x1="608.2" y1="806.8" x2="799.8" y2="217.2" />
          </g>
          <g clipPath="url(#dc-tile)">
            <g transform="rotate(18 512 512)" opacity="0.35">
              <rect
                className="dc-sheen"
                x="0"
                y="-200"
                width="200"
                height="1424"
                fill="url(#dc-sheen-fade)"
              />
            </g>
          </g>
        </svg>
        <h1 className="mt-6 text-2xl sm:text-3xl font-semibold tracking-tight">
          {t("heading")}
        </h1>
        <p className="mt-3 text-[15px] text-muted" style={{ lineHeight: 1.5 }}>
          {t.rich("subtext", {
            link: (chunks) => (
              // A real anchor so the download still works without JS (the
              // auto-download useEffect won't run if the bundle never hydrates).
              <a
                href={DOWNLOAD_URL}
                className="underline underline-offset-2 decoration-border hover:decoration-foreground transition-colors"
              >
                {chunks}
              </a>
            ),
          })}
        </p>
      </div>

      {/* Official links — reused from the Community page (no heading here) */}
      <div className="mt-14">
        <OfficialLinks heading={false} />
      </div>
    </main>
  );
}
