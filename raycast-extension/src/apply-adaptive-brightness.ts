import { Toast, getApplications, open, showToast } from "@raycast/api";

const dimmerBundleIdentifier = "com.dimmerapp.Dimmer";
const oneShotURL = "dimmer://apply-once";

export default async function applyAdaptiveBrightness() {
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Sampling display with Dimmer…",
  });

  const dimmer = (await getApplications()).find(
    (application) => application.bundleId === dimmerBundleIdentifier,
  );

  if (!dimmer) {
    toast.style = Toast.Style.Failure;
    toast.title = "Dimmer.app is not installed";
    toast.message =
      "Build the companion app and move it to /Applications, then grant Screen Recording access.";
    return;
  }

  try {
    await open(oneShotURL, dimmer);
    toast.style = Toast.Style.Success;
    toast.title = "Dimmer is applying a one-shot adjustment";
    toast.message = "Capture stops immediately after the local calculation.";
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = "Could not start Dimmer";
    toast.message =
      error instanceof Error
        ? error.message
        : "Open Dimmer.app once, then try again.";
  }
}
