# Bobber auto-zoom tracker — implementation handoff

This document is a self-contained spec for the auto-zoom feature prototyped in
`bobber-track.html`. It is written so another engineer (or LLM) can reproduce the
page from scratch and later port it into the main app. It covers **what was
built, why each decision was made, the exact algorithm/math, and how it maps
back into `index.html`.**

---

## 1. Background — the app and the problem

`index.html` is a single-file offline-first mobile web app ("Panfish Log") for
logging fishing trips. It has a hands-free clip feature (`window.FishClip`) that
keeps a rolling ~30s camera buffer while you fish; on a spoken trigger ("got a
bite" / "got him") it saves the last N seconds as an MP4 and attaches it to a
catch.

The camera pipeline is:

- `FishClip.start()` calls `navigator.mediaDevices.getUserMedia({video:{facingMode:"environment"…}, audio:true})` (index.html ~line 1099). That one `MediaStream` is the single source of truth.
- When WebCodecs is available, a Web Worker (`<script id="fcWorker">`, index.html ~line 281) keeps a rolling ring buffer of **encoded H.264 frames** (real pre-roll). The worker reads frames via `MediaStreamTrackProcessor`, draws each onto an `OffscreenCanvas` with **`ctx.drawImage(value,0,0)`** (index.html ~line 317), wraps the canvas in a `VideoFrame`, and encodes it.
- On save, the worker muxes the ring into an MP4 with `mp4-muxer`.

**The user's goal:** auto-zoom the camera onto the bobber (float) so clips are
tighter/more watchable, ideally hands-free.

We considered driving this from an Insta360 camera and concluded that's a native
(mobile-SDK) project, not a web change — see the roadmap note. This feature is
the tractable alternative: **software auto-zoom on the existing phone camera.**

---

## 2. Design decisions and rationale (the "why")

These are the load-bearing decisions. If you change them, change them
deliberately.

### 2.1 Track the bobber, NOT the fishing line
Fishing line is thin, translucent, low-contrast, and vanishes under glare or at
distance — a near-impossible tracking target. A bobber is engineered to be
seen: bright, saturated, roundish, high-contrast against water. **Track the
bobber.**

### 2.2 Digital crop, NOT optical zoom
The camera's optical `zoom` constraint (`track.applyConstraints({advanced:[{zoom}]})`)
exists on some Android Chrome but settles over hundreds of ms, can't be driven
per-frame, and doesn't exist on iOS. Useless for frame-accurate tracking.
Instead we **digitally crop**: pick a sub-rectangle around the bobber and scale
it to fill the output canvas. In the app this is literally the 9-argument form
of the existing draw call:
```js
// today (index.html:317):
ctx.drawImage(value, 0, 0);
// auto-zoom:
ctx.drawImage(value, sx, sy, sw, sh, 0, 0, W, H);
```
The zoom is baked into the recorded clip for free and composes with the worker's
existing rotate transform.

### 2.3 Color-blob detection, NOT ML (for v1)
HSV color thresholding finds a bright bobber in ~1 ms/frame on a downscaled
image, with no model, no training data, and no battery hit. An ML detector
(TF.js / MediaPipe / tiny YOLO) is more robust to weird lighting but needs a
labeled bobber dataset, runs many× slower on a phone, and drains battery.
**Start with color-blob; only escalate to ML if it demonstrably fails.**
Mitigation for color's fragility: **tap-to-calibrate** — the user taps the
bobber once and we sample its actual hue under the actual light.

### 2.4 The control loop matters more than the detector
Raw centroids jitter and the tracker will occasionally lose the bobber. Naïvely
wiring detection→crop yields a nauseating, pumping clip. Required:
- **EMA smoothing** on the crop rectangle so it glides.
- A **confidence gate**: when detection confidence drops below a threshold, ease
  the crop *back out to the full wide frame* instead of chasing a bad guess.

### 2.5 Don't destroy the wide shot (the key safety property)
This is a one-take, hands-free "capture the moment" tool. If the tracker guesses
wrong and we've already cropped, the wide footage is gone. The confidence gate
(2.4) is the primary defense. For the eventual port, the recommended posture is:
**drive the preview with the zoom first, and gate the destructive encode-path
crop behind the same confidence signal** — or, most conservative, record wide +
store the per-frame crop box as metadata and apply zoom as an opt-in post step.
The prototype demonstrates the gate so you can judge how safe live-crop is.

---

## 3. What `bobber-track.html` is

A **standalone test page** (no build step, no dependencies) that proves the
tracker in isolation before it touches `index.html`. It deliberately reuses the
app's visual theme (the `:root` CSS variables from `index.html`) and mirrors the
`fcWorker` frame-processing structure.

It is **detection + digital-zoom only** — it does NOT encode or save clips (that
pipeline already exists and is proven by `preroll-test.html`). Its job is to let
you watch, on your real bobber, whether color tracking holds and how the zoom
feels.

### UI layout
- **Start / Stop** camera buttons.
- **Recorded-output canvas** (top, 16:9): the digital-zoom crop — what the clip
  engine *would* record.
- **Wide scout canvas** (bottom, 16:9, tap target): the full frame with a
  **green** box on the detected bobber and a **cyan dashed** box showing the crop
  window.
- **HUD**: zoom×, confidence %, blob pixel count, fps, plus a confidence bar.
- **Color controls**: 5 hue presets (red/orange/yellow/chartreuse/pink) and
  tap-to-lock.
- **Tuning sliders**: hue tolerance, min blob size, max zoom, framing padding,
  smoothing factor, confidence gate.
- **Show match mask** toggle (paints matched pixels green so you can see exactly
  what the threshold catches) and **Reset**.

### Frame pump
The page uses a hidden `<video>` plus `requestVideoFrameCallback` (falling back
to `requestAnimationFrame`) to run once per displayed frame. This is the
main-thread analogue of the worker's `reader.read()` loop, chosen because it's
trivial to visualize. In the app the same logic lives in the worker loop.

---

## 4. The algorithm (exact, reproducible)

All detection runs on a small offscreen analysis canvas — **160 px wide**, height
set to preserve aspect ratio (≈90 for 16:9). Downscaling is the whole reason
detection is cheap; do not analyze full-res.

### 4.1 RGB → HSV
`h` in [0,360), `s` and `v` in [0,1]:
```js
function rgb2hsv(r,g,b){
  r/=255; g/=255; b/=255;
  const mx=Math.max(r,g,b), mn=Math.min(r,g,b), d=mx-mn;
  let h=0;
  if(d){ if(mx===r) h=((g-b)/d)%6; else if(mx===g) h=(b-r)/d+2; else h=(r-g)/d+4;
         h*=60; if(h<0)h+=360; }
  return [h, mx?d/mx:0, mx];
}
```

### 4.2 Circular hue distance (handles red's wrap at 0/360)
```js
function hueDist(a,b){ let d=Math.abs(a-b)%360; return d>180?360-d:d; }
```

### 4.3 The locked target
A tapped/preset color stored as `target = {h, s, v}`. From it we derive gates so
we ignore washed-out and dark pixels:
- `satMin = max(0.25, target.s * 0.45)`
- `valMin = max(0.20, target.v * 0.35)`

### 4.4 Detection — two passes
Draw the video onto the 160-wide canvas, `getImageData`, then:

**Pass 1 — threshold.** A pixel *matches* iff
`s >= satMin && v >= valMin && hueDist(h, target.h) <= hueTol`.
Collect all matching pixel coords; accumulate centroid `(cx,cy)` and count `n`.
If `n < 4`, return confidence 0.

**Pass 2 — outlier rejection.** Keep only matches within radius `0.28 * AW`
(≈45 px) of the pass-1 centroid; recompute centroid and bounding box from those.
This stops a stray red glint elsewhere in frame from dragging the box. If the
surviving count `n2 < 4`, return confidence 0.

Bounding box `bw × bh` (min 1 each).

### 4.5 Confidence score
Blend absolute size against solidity (how densely the box is filled):
```
solidity = n2 / (bw * bh)
sizeConf = min(1, n2 / max(6, minBlob))
conf     = clamp01( sizeConf * min(1, solidity / 0.20) )
```
Rationale: a real bobber is a solid, appropriately-sized blob. A few scattered
matched pixels (low solidity) or a tiny blob (low size) → low confidence → the
gate zooms out.

### 4.6 Crop-window math
Scale analysis coords to frame coords (`scaleX = fw/AW`, `scaleY = fh/AH`).
```
bobW = bw*scaleX, bobH = bh*scaleY
cw = max(bobW, bobH) * pad          // square-ish crop sized off the bobber (pad≈3.2)
cw = clamp(cw, fw/maxZoom, fw)      // never tighter than maxZoom, never bigger than frame
ch = cw * (fh/fw)                   // keep output aspect ratio
if (ch > fh){ ch = fh; cw = ch*(fw/fh); }
x = clamp(cx*scaleX - cw/2, 0, fw-cw)
y = clamp(cy*scaleY - ch/2, 0, fh-ch)
```
`{x,y,cw,ch}` is the *target* crop in frame pixels.

### 4.7 Gate + smoothing (per frame)
```
if (conf >= gate && haveDetection) target = {x,y,w:cw,h:ch}
else                               target = {x:0,y:0,w:fw,h:fh}   // ease back to wide

// EMA toward target (smooth ≈ 0.15; smaller = smoother/slower)
crop.x += (target.x - crop.x) * smooth
crop.y += (target.y - crop.y) * smooth
crop.w += (target.w - crop.w) * smooth
crop.h += (target.h - crop.h) * smooth
```
Displayed zoom = `fw / crop.w`.

### 4.8 Render
- Wide canvas: `drawImage(video,0,0,fw,fh)`, then stroke the green detection box
  and the cyan dashed crop rect.
- Output canvas: `drawImage(video, crop.x,crop.y,crop.w,crop.h, 0,0,fw,fh)` — the
  digital zoom.

### 4.9 Tap-to-lock
Map the tap's client coords to analysis-canvas coords, average a 5×5 neighborhood
for stability, `rgb2hsv` it, store as `target`.

### Default tunables
`hueTol=18°, minBlob=30px, maxZoom=3.0×, pad=3.2×, smooth=0.15, gate=0.35`.

---

## 5. Porting into `index.html` (the real integration)

The feature lives entirely inside the `fcWorker` script.

1. **Move detection into the worker loop.** In `runVideo()` (index.html ~line
   313), the worker already has each `VideoFrame` (`value`). Draw a downscaled
   copy to a 160-wide `OffscreenCanvas`, `getImageData`, and run §4.1–4.5. Keep a
   persistent `crop` state and `target` (the locked color) in worker scope.
2. **Replace the draw at line 317.** Change
   `ctx.drawImage(value,0,0)` → `ctx.drawImage(value, crop.x,crop.y,crop.w,crop.h, 0,0,W,H)`
   after updating `crop` via §4.7. Mind the existing `rotate` branch (lines
   315–318): apply the crop as the *source* rect; the rotate transform stays on
   the destination.
3. **Get the locked color to the worker.** Add a preview tap handler on
   `#camPreview` in `FishClip` that samples the color (§4.9) and
   `worker.postMessage({type:'target', hsv})`. Persist it in `S.prefs` so it
   survives reloads. Offer the hue presets in settings as a fallback.
4. **Safety posture (see §2.5).** Recommended first cut: apply the crop only to a
   *preview* path and keep the encode path wide, OR gate the encode-path crop
   behind `conf >= gate` with a conservative `maxZoom` (~1.5–2×) and generous
   `pad`. Do not ship an ungated destructive crop.
5. **Perf.** Detection on 160×90 is ~1 ms; it runs inside the same loop that
   already encodes at 30 fps, so budget accordingly. If it ever costs too much,
   detect every 2nd–3rd frame and interpolate `crop`.

---

## 6. How to test

1. Serve over **HTTPS** (camera needs a secure context). Cloudflare Pages, or any
   https static host; `localhost` also counts as secure.
2. Open `bobber-track.html` on the phone. Tap **Start**, allow the camera.
3. Tap the bobber in the wide (bottom) view to lock its color (or pick a preset).
4. Move the rod. Watch two things:
   - Does the **green box stay on the bobber**?
   - When the bobber leaves frame / is occluded, does **confidence fall to red**
     and the crop **ease back to wide** (rather than snapping to a false target)?
5. Use **Show match mask** to see exactly which pixels match, and the sliders to
   dial `hueTol` / `minBlob` / `gate` for your bobber and water.
6. Decision: if color-blob holds on real gear → port per §5. If it struggles
   (glare, muddy water, multiple bright objects) → that's the signal to try the
   tap-calibrated ML path instead.

---

## 7. Files
- `bobber-track.html` — the prototype described here (standalone, no deps).
- `index.html` — the app; integration seam is `fcWorker` ~lines 313–320.
- `preroll-test.html` — proves the WebCodecs ring-buffer + muxer save path
  (reuse it if you add record-and-save to the tracker page).
