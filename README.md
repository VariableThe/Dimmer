# Dimmer

Dimmer is a native macOS menu-bar utility that locally analyzes a small,
downsampled stream of the built-in display and gently adapts perceived
brightness to the visible content. It targets macOS 14+ and uses SwiftUI,
AppKit, Core Graphics, and ScreenCaptureKit with no third-party dependencies.

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

## Run it

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
grant access. The capture stream is local-only: Dimmer immediately converts each
low-resolution frame into numeric statistics and never writes or uploads image
data.

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
- Capture output is limited to a low-resolution SDR BGRA stream and analysis
  slows while content is stable.
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
