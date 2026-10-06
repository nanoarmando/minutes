## Why

Client detection only reads the transcript, but in many calls nobody says the client's name: it is in the calendar
event title ("DrGreenlife - Followup") and in the attendees' email domains (`@drgreenlife.com`). The first real
client meeting recorded with Minutes got no client tag for that reason. That meeting was also left untagged until
the user pressed Re-tag: a tagging call that fails, or that is cut short when Minutes quits, is lost silently.

## What Changes

- Attendee email domains decide the clients: every business domain that is not the user's organization is a
  client; the model names it (reusing existing client tags) and only falls back to the title and transcript when
  there are no client domains.
- A new "Your email addresses" field in Settings › Tags lists the addresses the user joins meetings with. The
  address found among the event's attendees tells which organization the user represents in that meeting
  (vnstudios.com or tvp.com); when it cannot be known, all of the user's domains are excluded. Personal email
  domains are never organizations.
- The sidecar keeps the event details needed to re-tag later (attendee emails and the user's own domain) and the
  tagging state.
- Tagging becomes reliable: a note stays pending until tagging succeeds, pending notes are retried at the next
  launch, and a failure is shown in the meeting detail with Re-tag.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `meeting-tags`: "Your email addresses" setting, domain-based client detection, pending tagging with retry and a
  visible error.
- `meeting-notes`: the sidecar also stores the calendar event details and the tagging state.
- `app-shell`: the Tags settings section lists the new field.

## Impact

- Code: calendar event lookup (attendee emails, own domain), preferences, tagging request and rules, sidecar model,
  launch-time retry, meeting detail error state, Settings › Tags.
- Notes: no change to the Markdown front matter; new optional fields in the sidecar.
- Notes recorded before this change are re-tagged with the title and front matter attendees, with the domains of "Your email addresses" as the user's organization.
- Privacy: attendee names and email domains are sent to the summary provider together with the transcript, which
  that provider already receives.
