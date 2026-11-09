# SmartWindow v0.6.0

## Highlights
- Device HUD in the notch: when a Bluetooth or USB device connects, disconnects or runs low, the notch shows its icon, name and battery for a moment. It works with any device; one that does not report its battery shows Connected with no number.
- AirPods and other devices with several batteries get a card under the notch with one ring per part (Left, Right, Case).
- Low battery: the battery turns orange at 20% and red with Low at 10%. Each step is announced once until the battery recovers.

## Changes
- New optional Bluetooth permission in Settings → Permissions. With it, Bluetooth devices show the moment they connect or disconnect; without it, some take up to a minute.
- Device events queue behind each other; a volume or Focus change still shows at once.
- The device HUD lets every click through, and VoiceOver reads each event as one sentence.
- Devices already connected when SmartWindow starts are not announced.

## Distribution
- macOS 13 or later; this release ZIP contains an Apple Silicon (arm64) build.
- The release ZIP is signed with Developer ID and notarized by Apple.

## Known validation limits
- The device HUD was checked with probes and offscreen renders of sample devices. It was not yet tested with real devices connecting and disconnecting.
- Which devices report a battery, and whether they report charging, depends on the device. USB devices are covered when they are input devices (keyboards, mice, controllers).
- If a volume or Focus change interrupts a device HUD, that device event is not shown again.
