# Dimmer for Raycast

**Apply Adaptive Brightness** wakes the Dimmer companion only long enough to
sample the built-in display, calculate an effective brightness level, and
apply it. It does not leave a ScreenCaptureKit stream running.

## Setup

1. Build the companion from the repository root with `bash Scripts/build-app.sh`.
2. Move `build/Dimmer.app` to `/Applications` and open it once.
3. Grant Dimmer Screen Recording permission and ensure Adaptive Brightness is
   enabled in its menu-bar panel.
4. Run `npm install` and `npm run dev` in this directory to install the
   development extension into Raycast.

The extension locates `com.dimmerapp.Dimmer` and opens its documented
`dimmer://apply-once` URL. It never receives screenshots or screen statistics.

The current public macOS API cannot set a MacBook's physical backlight. Dimmer
therefore applies its documented click-through overlay fallback.

## Store publishing

Before submitting to the Raycast Store, replace the `author` field in
`package.json` with the maintainer's actual Raycast handle. The repository uses
the GitHub handle as a development placeholder, but Raycast verifies this field
against its own accounts during lint and publish.
