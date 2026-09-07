# Dimmer

Dimmer is a macOS companion for the included Raycast extension. It locally
analyzes one small, downsampled sample of the built-in display, applies the
resulting effective brightness, then releases the capture stream. It targets
macOS 14+ and uses SwiftUI, AppKit, Core Graphics, and ScreenCaptureKit with
no third-party dependencies.

## Important capability result

There is no current supported public macOS API for setting the physical
backlight of a MacBook's built-in display. Dimmer intentionally does not call
private CoreDisplay/DisplayServices APIs or use the deprecated
`CGDisplayIOServicePort` bridge. See [the API investigation](Docs/API_CAPABILITIES.md).

Consequently, this MVP uses a click-through, built-in-display-only black overlay
as a truthful fallback. It can reduce perceived brightness, but it does not
claim to read or increase the hardware brightness. The `BrightnessController`
abstraction keeps a future public native controller isolated from the rest of
the app. In this fallback, the target and min/max controls describe Dimmer's
**effective overlay level**, not a physical panel-backlight percentage.

## Use it with Raycast

1. Build and install the companion application in `/Applications`:

   ```bash
   bash Scripts/build-app.sh
   cp -R build/Dimmer.app /Applications/Dimmer.app
   open /Applications/Dimmer.app
   ```

2. In Dimmer's menu bar panel, grant Screen Recording access and leave
   **Adaptive Brightness** enabled.
3. Install the development extension from `raycast-extension` using
   `npm install` then `npm run dev`. Run **Apply Adaptive Brightness** in
   Raycast whenever you want a fresh adjustment.

Raycast opens `dimmer://apply-once`. Dimmer captures one low-resolution frame,
converts it to numeric statistics, applies the result, and immediately stops
ScreenCaptureKit. The applied overlay remains active; no periodic capture runs
unless you explicitly choose **Start Updates** from the menu bar.

## Run the companion directly

Build the local application bundle so macOS receives the Screen Recording usage
description:

```bash
bash Scripts/build-app.sh
open build/Dimmer.app
```

For source-only UI development, you can also run:

```bash
swift run Dimmer
```

The first time you enable adaptive analysis, select **Grant Screen Recording
Access** in the menu-bar panel. macOS may require relaunching the app after you
grant access. Use **Apply Once** for the battery-friendly behavior or **Start
Updates** for the optional continuous mode. The capture stream is local-only:
Dimmer immediately converts each low-resolution frame into numeric statistics
and never writes or uploads image data.

## Adaptive model

The frame analyzer converts sRGB values to linear-light relative luminance:

```text
Y = 0.2126 R_linear + 0.7152 G_linear + 0.0722 B_linear
```

It records mean, median, min/max, P90/P95/P99, variance, and configurable dark
and bright pixel fractions. The content score weights the median and P90/P95
more strongly than the maximum. A bright pixel occupying a tiny fraction of the
frame therefore has negligible influence, while a mostly white page scores
highly.

The deterministic engine starts from the user comfort target, lowers it for
bright content, raises it for dark content, and adds a nonlinear ambient term
only when a real ambient value is available. A dark-room bias defaults to zero;
when set, it is an explicit user preference rather than a fabricated sensor
estimate. The engine applies min/max constraints, hysteresis, an exponential
low-pass response, and a maximum rate of change. A manual slider action pauses
adaptive writes for the configured duration.

macOS supplies no documented public MacBook ambient-light reading, so this MVP
reports that source as unavailable rather than fabricating a measurement. Its
provider protocol is ready for a future supported source.

## Design notes

- Only `CGDisplayIsBuiltin` identifies a target. External displays are listed
  for diagnostics but are never changed.
- `NSWorkspace.activeSpaceDidChangeNotification` requests a fresh analysis; no
  brightness state is stored per Space.
- `CGDisplayRegisterReconfigurationCallback` restarts capture/repositions the
  fallback when displays change.
- Raycast's one-shot command releases capture immediately after its first
  low-resolution SDR BGRA analysis; the optional continuous mode slows its
  analysis while content is stable.
- The fallback overlay ignores mouse events, does not accept focus, and the
  capture filter excludes Dimmer itself to avoid feedback.
- The fallback cannot guarantee exclusion from every third-party screenshot
  mechanism; it is excluded from Dimmer's own analysis rather than relying on
  legacy window-sharing flags.

## Verify

```bash
swift build
swift test
```

The test suite covers luminance statistics, bright/dark-content responses,
ambient changes, constraints, smoothing/hysteresis, and manual override logic.
