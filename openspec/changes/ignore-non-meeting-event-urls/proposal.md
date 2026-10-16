## Why

The event URL field counts as a meeting link whatever it points to. Tools such as Blockout fill it with app links (`blockout://block/...`), so focus blocks without guests get a recording suggestion and notes store a link that is not a call.

## What Changes

- The meeting link is the first Zoom, Google Meet, Microsoft Teams or Webex link found in the event URL, location or notes, in that order.
- An event URL on any other host or scheme is ignored, both for the recording suggestion and for `meeting_link` in the note.

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `calendar`: the "Event data in the note" requirement changes how the meeting link is chosen, which also narrows the events that qualify for a suggestion.

## Impact

- `Sources/Minutes/Calendar/CalendarService.swift` (`meetingLink(of:)`).
- `README.md` and `AGENTS.md` if they describe the link source.
- Existing notes are not rewritten.
