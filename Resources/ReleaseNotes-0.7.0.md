# SmartWindow v0.7.0

## Highlights
- Call HUD in the notch: join a call and a card drops with the app, a waveform and the time, then folds into wings around the camera, with the app on the left and a green timer on the right. Point at the notch to bring the card back.
- When you hang up, the card shows Call ended and the total for a moment, then your music comes back.
- Official icons: each call app shows its own icon, taken from the installed app.
- Web calls: a call in Chrome, Safari, Arc, Dia, Firefox, Edge or Brave is named after the service in the browser window title (Google Meet, Teams, Zoom, Webex, WhatsApp, Slack, Discord, Jitsi Meet), with a small browser mark.

## Changes
- A call is a call app using the microphone: FaceTime (and iPhone calls on the Mac), Zoom, Teams, WhatsApp, Discord, Slack, Webex, Skype, Telegram, Signal and browsers. Dictation, Voice Memos and other apps using the microphone are not calls.
- New optional Microphone permission in Settings → Permissions. With it, the waveform follows your voice; without it, it just pulses. SmartWindow only measures how loud you are while a call is on; it keeps no audio and sends none.
- Volume, brightness, Focus and device changes still show over the call, also while the call card is open.
- VoiceOver says when a call starts and when it ends, with its length.

## Distribution
- macOS 13 or later; this release ZIP contains an Apple Silicon (arm64) build.
- The release ZIP is signed with Developer ID and notarized by Apple.

## Known validation limits
- The call HUD needs macOS 14 or later; on macOS 13 there is no call HUD.
- Naming a web call is a best guess from the browser window titles: only the active tab of each window is in its title, so a call in a background tab shows the browser until you look at that tab once. It uses the Accessibility permission.
- A web service shows the icon of its Mac app only when that app is installed; otherwise, and for Meet, a colored badge.
- Incoming calls (ringing) are not shown, only calls you are in.
- Tested live with calls in Google Meet and FaceTime; other apps were checked with probes and offscreen renders.
