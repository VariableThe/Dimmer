# Dimmer MVP: macOS capability investigation

Investigated on macOS 15.7 with the macOS 15 SDK. This document deliberately
distinguishes supported public APIs from APIs that happen to be present in a
framework header.

## Decision summary

| Need | Public API used by the MVP | Result |
| --- | --- | --- |
| Find the internal panel | `CGDisplayIsBuiltin` | Supported |
| Detect display configuration changes | `CGDisplayRegisterReconfigurationCallback` | Supported |
| Analyze visible display content | ScreenCaptureKit (`SCShareableContent`, `SCContentFilter`, `SCStream`) | Supported, Screen Recording permission required |
| Ask/check Screen Recording permission | `CGRequestScreenCaptureAccess` / `CGPreflightScreenCaptureAccess` | Supported |
| Notice a Space change | `NSWorkspace.activeSpaceDidChangeNotification` | Supported; used only to request a fresh analysis, never for profiles |
| Physical built-in-panel brightness | No current supported public API | Unavailable in this MVP |
| Ambient-light sensor value | No documented public API for the built-in Mac ambient-light sensor | Unavailable in this MVP |
| Accessibility permission | None | Not required |

## Hardware brightness limitation

Apple does not expose a current, supported, high-level public macOS API for
reading or setting the physical backlight of the built-in display. IOKit does
export `IODisplayGetFloatParameter` and `IODisplaySetFloatParameter`, but the
public Core Graphics bridge normally used to get the required display service,
`CGDisplayIOServicePort`, is deprecated with **no replacement**. The SDK header
also marks that bridge as "No longer supported" (deprecated since macOS 10.9).

Dimmer therefore does **not** call a private framework, invoke the deprecated
bridge, synthesize brightness-key events, or use a kernel extension. Its
`NativeBrightnessController` truthfully reports that supported hardware control
is unavailable. `FallbackBrightnessController` then uses
`OverlayBrightnessController`, a local, click-through black overlay only on the
built-in display. The overlay can reduce perceived brightness; it cannot claim
to brighten the hardware panel beyond the system setting.

For the same reason, the MVP labels its target and min/max values as effective
overlay brightness. They are not presented as physical panel-backlight values.

The abstraction is intentional: a future Apple-supported physical-brightness
API can replace the native controller without changing the analyzer or engine.

## Screen analysis and privacy

ScreenCaptureKit captures just the selected built-in `SCDisplay` at a small
configured size and SDR BGRA format. The app excludes its own process from the
stream so its fallback overlay cannot feed back into the content score. Frames
are converted to numeric luminance statistics immediately on a serial queue;
raw images and pixel buffers are not retained, written, or transmitted.

The fallback overlay is excluded from Dimmer's own ScreenCaptureKit filter to
avoid feedback. Other capture mechanisms may still show it. Apple documents
`NSWindow.SharingType.none` as a legacy value that macOS no longer uses and
explicitly says not to use it to omit captured content, so Dimmer does not make
that false promise.

ScreenCaptureKit requires Screen Recording permission. The bundled app includes
`NSScreenCaptureUsageDescription`, explains that analysis is local-only before
requesting permission, and offers a button to open the Privacy & Security pane.
Apple notes that a newly granted permission can require an app restart before a
capture stream works.

## Ambient light

The Mac's automatic-brightness feature can consume the built-in ambient-light
sensor, but macOS currently documents no public API that provides its reading to
third-party apps. `AmbientLightManager` therefore reports `.unavailable` rather
than inventing an estimate. A nonzero dark-room bias is an explicit user
preference, not an implied sensor reading. The adaptive engine accepts an
optional normalized ambient value through `AmbientLightProviding`, making a
future supported provider additive without changing its model.

## Spaces and display changes

There is one selected physical built-in display. A Space switch changes what
ScreenCaptureKit sees on that display; it never creates a per-Space brightness
profile. The workspace notification is used only to expedite the next sample.
`CGDisplayRegisterReconfigurationCallback` restarts capture and repositions the
fallback overlay after a real display configuration change. External displays
are enumerated for diagnostics but never adjusted.

## Primary Apple references

- [ScreenCaptureKit overview](https://developer.apple.com/documentation/screencapturekit)
- [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Screen capture permission preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())
- [Screen capture permission request](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess())
- [Built-in display detection](https://developer.apple.com/documentation/coregraphics/cgdisplayisbuiltin(_:))
- [Display configuration callback](https://developer.apple.com/documentation/coregraphics/cgdisplayregisterreconfigurationcallback(_:_:))
- [Deprecated `CGDisplayIOServicePort`](https://developer.apple.com/documentation/coregraphics/cgdisplayioserviceport(_:))
- [Space-change notification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)
- [Legacy `NSWindow.SharingType.none`](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none)
