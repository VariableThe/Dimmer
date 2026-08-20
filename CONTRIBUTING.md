# Contributing to Dimmer

Thank you for helping improve Dimmer. This is a native Swift Package Manager
application for macOS 14 and later.

## Local setup

Use a current Xcode toolchain with macOS development support. From the project
root, run:

```bash
swift build
swift test
```

To create the local application bundle used for manual testing:

```bash
bash Scripts/build-app.sh
open build/Dimmer.app
```

Screen Recording permission is required to exercise the adaptive analysis path.
Never commit generated `.build` or `build` output.

## Making a change

Keep pull requests small and describe both the user-visible behavior and the
reason for the change. Add or update tests whenever behavior in the adaptive
engine or frame analysis changes. For UI, capture, permission, display, or
overlay changes, manually test the relevant path on macOS and record what you
checked in the pull request.

Match the existing Swift style; the project does not currently enforce a
formatter or linter. Do not introduce new dependencies, secrets, generated
artifacts, or broad unrelated reformatting without discussing them first.

## Privacy and platform boundaries

Dimmer processes a downsampled screen-capture stream only in memory. It must
not store, transmit, or log image frames. Any changes affecting capture or
permissions should preserve this property.

Use documented public macOS APIs only. In particular, do not add private
CoreDisplay or DisplayServices calls, deprecated display-service bridges, or
simulated brightness-key input. The current brightness fallback is an overlay,
not physical backlight control; user-facing copy and tests must preserve that
distinction.

## Before opening a pull request

Run `swift build` and `swift test`, update documentation for changed behavior,
and complete the pull request template. CI repeats the build and test suite on
macOS 15 for pushes to `main` and pull requests.
