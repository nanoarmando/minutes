## Context

`meetingLink(of:)` returns `event.url` unconditionally and only filters links detected in the location and notes against `meetingHosts`. Blockout writes `blockout://` URLs into the event URL field.

## Decisions

- **D1. One host check for every source.** Candidates are `event.url` followed by the links detected in the location and notes; the first whose host matches `meetingHosts` wins. Alternative rejected: only rejecting non-http schemes, which would still accept project or document pages.

## Risks / Trade-offs

- A real call link in the URL field on a host outside the list (for example Whereby) is no longer used; the list can grow when needed.
