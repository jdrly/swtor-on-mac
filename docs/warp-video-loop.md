# The warp as a video loop (parked)

A design note, not built. The main window's warp (`src/native/Warp.swift`) is drawn by SwiftUI,
a `Canvas` in a `TimelineView` at 24 frames a second. Measured with `scripts/ui-snapshot.sh`
(2026-10-21, a 960 × 680 window on the virtual display, the app's own GPU time from the GPU
driver's AppUsage):

| | app GPU |
|---|---|
| the warp at 24 fps, half resolution | 1.7 % |
| an empty canvas on the same clock, drawing nothing | 1.6 % |
| without the glass buttons | 1.8 % |
| 20 fps | 1.5 % |
| paused | 0 % |

What costs is that a frame happens at all (a Core Animation transaction, the window rendered
again), not what it draws. So the app stops the warp 30 s after the last input
(`Tuning.idleStop`). This note is the other way: continuous motion at a fraction of the cost,
with no app frames at all.

## Approach

- Render the warp once, offline, as a seamless loop: `WarpField.draw` made periodic (each star's
  cycle a whole number of loops, the speed constant, no jump at the start), e.g. 8 s at 30 fps.
- Encode it as HEVC with alpha, or as two opaque variants for dark and light (the site's
  near-black and paper under the stars). A low bitrate is enough: dark, sparse, soft.
- Play it in an `AVPlayerLayer` (`AVPlayerLooper`) behind the content, in place of the `Warp`
  view. The media engine decodes it and Core Animation shows the frames: no SwiftUI frames, no
  app-side drawing.
- Keep what the current warp does: paused while the window is not in front or not visible,
  stopped while SWTOR runs, a still frame with Reduce Motion, light and dark.
- The jump at the start (near-still, the punch, then cruise) as a separate short clip before the
  loop, or left out.

## Risks

- **The seam:** the loop must not show where it starts again. Periodic stars and a constant
  speed solve it in the source; check frame 0 against the last frame.
- **Scaling:** the window is resizable (520 × 640 at least). The jump point sits near the top
  right, so the video can't just be stretched. Options: render it larger, place it by the jump
  point and crop the rest (`resizeAspectFill` with an anchor), or a few sizes.
- **Size:** the app grows by the videos (two appearances, maybe two sizes). Aim for under
  2–3 MB in all.
- **Colour:** the background must match `Brand.bg` exactly (video colour space and range), or
  the edge shows. With alpha over the drawn background, it doesn't matter.
- **Is it really cheaper?** Video decoding and showing a layer have a cost too, so measure
  instead of assuming.

## Measurement plan

- Its own branch, off feat/app-redesign once that is merged; A/B against the Canvas warp.
- `scripts/ui-snapshot.sh` with a `WARP=video` variant: the app's GPU, CPU (instructions) and
  WindowServer's GPU, several rounds, on an unlocked Mac with the display awake.
- And on Jan's screen, with Jan: Activity Monitor's GPU column, and the look side by side (the
  seam, the softness, the motion).
- The bar: clearly below the Canvas warp's cost while it runs, and looking the same.
