## Context

Event-start suggestions live in `CalendarService` with `MeetingNotifications` categories. Capture uses Core Audio
already (process tap). macOS 14.2+ exposes per-process audio objects.

## Goals / Non-Goals

**Goals:** detect calls without permissions or new dependencies; never act without the user's click.
**Non-Goals:** identifying which browser tab uses the microphone; auto-start or auto-stop; deduplicating with
calendar suggestions.

## Decisions

### D1. Which apps use the microphone
`CallDetector` (Capture/) reads `kAudioHardwarePropertyProcessObjectList` and, for each process object,
`kAudioProcessPropertyIsRunningInput`, `kAudioProcessPropertyBundleID` and `kAudioProcessPropertyPID` (macOS 14.2+,
no TCC prompt). It polls every 2 seconds on a background queue while the setting is on (cheaper and simpler than
per-process listeners that come and go), skips Minutes' own PID, and keeps a map bundle ID → first seen time.
Meeting apps are one constant list of bundle IDs: us.zoom.xos, com.microsoft.teams2, com.microsoft.teams,
com.tinyspeck.slackmacgap, Cisco-Systems.Spark, com.webex.meetingmanager, com.apple.FaceTime, com.hnc.Discord,
com.google.Chrome, company.thebrowser.Browser, com.apple.Safari, com.microsoft.edgemac, com.brave.Browser,
org.mozilla.firefox. Browser helper processes are matched by bundle ID prefix.
*Alternative:* `kAudioDevicePropertyDeviceIsRunningSomewhere` on the input device – rejected: it cannot tell which
app, so dictation would trigger it.

### D2. Events
The detector emits `callStarted(appName)` when one meeting app has used the input for 10 s, at most once until that
app stops using it; and `callEnded` when, during a recording in which a meeting app used the input, none has for
10 s. `AppEnvironment` turns them into notifications only when allowed (not recording for start; recording for end;
setting on). One "end" question per recording unless a meeting app uses the microphone again.

### D3. Notifications
Two categories in `MeetingNotifications`: "call-start" (Start recording, Dismiss) and "call-end" (Stop & summarize,
Keep recording), handled by the existing delegate. App names come from the running application's localized name.

## Risks / Trade-offs

- [Browsers use the microphone for non-meeting sites] → the 10-second threshold and one suggestion per continuous use;
  the switch turns it off.
- [Some Core Audio process properties may be missing for sandboxed helpers] → match by bundle ID prefix and ignore
  processes without a bundle ID.
- [Polling cost] → one property read per audio process every 2 s, only while the setting is on.
