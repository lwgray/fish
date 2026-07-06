# Can we do a rolling "pre-roll" video buffer in an iOS PWA? — Research verdict

**Question:** Continuously keep the last ~15–30 s of camera video so a voice trigger can save footage from *before* the trigger, entirely in a web app / installed PWA on iPhone, no native code.

**Verdict:** **Not reliably with the current MediaRecorder approach. A different API (WebCodecs) makes it *technically* possible on iOS 18+, but it's unproven, video-only until iOS 26, memory-risky, and — the dealbreaker for a PWA — it stops the moment the phone locks or the app is backgrounded. Rock-solid pre-roll requires a native wrapper.**

---

## Why the current approach produces empty/blank clips on iPhone

The app keeps the first ("header") MediaRecorder chunk + a rolling window of recent chunks and concatenates them on trigger. That works on Android (WebM) but fails on iOS for three independent, documented reasons:

1. **iOS records fragmented MP4, not WebM.** Before Safari 18.4 (Mar 31 2025) iOS Safari's MediaRecorder only output MP4 (H.264/AAC); `isTypeSupported('video/webm')` was `false`. [webkit.org/blog/11353](https://webkit.org/blog/11353/mediarecorder-api/), [webkit.org/blog/16574 (18.4)](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/)
2. **`timeslice` has historically not emitted periodic chunks on iOS** — `ondataavailable` fired only once, on `stop()`, through iOS 16.x (improving but version-sensitive since). If chunks don't stream, the rolling buffer never fills → near-empty clip. [MDN compat #10676](https://github.com/mdn/browser-compat-data/issues/10676), [WebKit #202233](https://bugs.webkit.org/show_bug.cgi?id=202233), [Apple forum #662277](https://developer.apple.com/forums/thread/662277)
3. **You can't cleanly drop-the-middle and splice fMP4.** Safari's fMP4 has the `moov` init at the front but with **zeroed duration fields**, and media fragments carry timestamps relative to the whole recording — so `[init] + recent-fragments` (dropping the middle) generally won't play/seek without remuxing. Only in-order concatenation of a *complete* recording is the supported path. [addpipe, May 2026](https://blog.addpipe.com/duration-in-mp4-files-produced-by-chrome-safari/), [MDN dataavailable](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/dataavailable_event)

## Why it re-prompts for permissions

- **Standalone PWAs don't persist camera/mic permission** — cold start re-prompts, still open as of Feb 2026. [WebKit #215884](https://bugs.webkit.org/show_bug.cgi?id=215884)
- SPA navigation historically stopped capture tracks and re-prompted (route-change bug, fixed 14.5) — and starting speech recognition after an `await` loses the user-gesture context it needs. [WebKit #215884](https://bugs.webkit.org/show_bug.cgi?id=215884)

## The real modern path — WebCodecs (and its limits)

The surprising good news: **`VideoEncoder` (encode, not just decode) has worked on iOS Safari since 16.4** (Mar 2023) — H.264; HEVC since 17.4. So a true ring buffer (encode frames → keep a ring of `EncodedVideoChunk`s → mux on demand with **Mediabunny**, which supersedes mp4-muxer) is architecturally viable. [caniuse VideoEncoder](https://caniuse.com/mdn-api_videoencoder), [Safari 16.4 notes](https://webkit.org/blog/13966/webkit-features-in-safari-16-4/)

But the caveats are serious:
- **`MediaStreamTrackProcessor`** (to get camera `VideoFrame`s) is **iOS 18.0+ and worker-only** on WebKit — the track must be handed to a Web Worker. [caniuse MSTP](https://caniuse.com/mdn-api_mediastreamtrackprocessor), [Safari 18 notes](https://webkit.org/blog/15443/news-from-wwdc24-webkit-in-safari-18-beta/)
- **Audio (`AudioEncoder`) only lands in Safari 26 (iOS 26)** — a video-only clip until then. [caniuse WebCodecs](https://caniuse.com/webcodecs)
- **Real iPhone failure modes:** low-memory crashes with large in-memory buffers (exactly what a ring buffer is), silent transcode hangs, keep bitrate ≤ ~10 Mbps. [mediabunny #184](https://github.com/Vanilagy/mediabunny/issues/184), [#333](https://github.com/Vanilagy/mediabunny/issues/333)
- **No public dated demo proves the full camera→VideoEncoder→ring→MP4 pipeline on a physical iPhone.** You'd be validating it yourself.

## The dealbreaker for any pure-web pre-roll: backgrounding & lock

In an installed PWA, **capture stops when the app is backgrounded or the screen locks, and the camera often won't resume.** Screen Wake Lock itself was broken in PWAs until iOS 18.4. So even a perfect ring buffer only records while the app is foregrounded and awake. [firt.dev/notes/pwa-ios](https://firt.dev/notes/pwa-ios/), [WebKit #254545](https://bugs.webkit.org/show_bug.cgi?id=254545)

## Bottom line & options

| Path | Pre-roll? | Reliability on iPhone | Effort |
|---|---|---|---|
| **Record from "got a bite" → outcome** (MediaRecorder, one continuous clip) | No | High — always a playable clip | Small |
| **WebCodecs ring buffer** (iOS 18+, video-only) | Yes (while foregrounded/awake) | Unproven; memory-risky; dies on lock/background | Large R&D + on-device testing |
| **Native wrapper (Capacitor + AVFoundation)** | Yes, truly (incl. background) | High | Large (native build, app store) |

**Recommendation:** ship the reliable *record-from-trigger* fix now (kills the empty-clip + permission bugs), keep pre-roll as a native-wrapper goal, and treat the WebCodecs ring buffer as an optional experiment for iOS 18+ devices only.
