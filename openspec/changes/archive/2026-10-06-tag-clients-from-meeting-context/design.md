## Context

`TagService` sends only the transcript (or excerpts) and the existing tags; errors are swallowed and the
post-save task is not persisted, so a failure or a quit leaves the note untagged. `CalendarService` builds
`EventInfo` (title, calendar, attendee display names, meeting link) and skips the current user. `EventInfo` is
stored in `session.json` and written to front matter; the sidecar does not keep it.

## Goals / Non-Goals

**Goals:** clients from attendee domains; the right "own organization" per meeting account; tagging that is never
lost silently.
**Non-Goals:** re-reading the calendar when re-tagging old notes; background retries while the app runs.

## Decisions

### D1. Event data in the sidecar
`EventInfo` gains `attendeeEmails: [String]` (non-current-user participants with a `mailto:` address) and
`ownDomain: String?`. Front matter keeps `attendees` as display names; the sidecar stores the whole `EventInfo` as an
optional `event` field. Old sidecars decode with `event == nil`.

### D2. Own domain and client domains (deterministic, in Swift)
The user's address = the attendee address that matches the preference `userEmails` (case-insensitive), else the
participant with `isCurrentUser`, else the calendar source title when it is an email address; `ownDomain` is its
domain. Attendees matching `userEmails` are dropped from `attendeeEmails`. A fixed personal list (gmail.com, googlemail.com, outlook.com, hotmail.com, live.com, icloud.com, me.com,
mac.com, yahoo.com, proton.me, protonmail.com) is discarded everywhere. Own set = `{ownDomain}` when known, else the domains of `userEmails` (addresses normalized: lowercase,
trimmed). Client domains =
attendee domains minus own set minus personal, ordered by attendee count, at most two. Domains are compared by
registrable suffix match so `mail.drgreenlife.com` matches `drgreenlife.com`.
*Alternative:* letting the model decide everything – rejected: domains are a reliable signal and the rule
"every other business email is a client" is the user's explicit choice.

### D3. Model's role
The tagging call receives a header before the transcript: `Meeting title: …`, `Client domains: drgreenlife.com`
(or none), `User's organization: vnstudios.com` (or the domains of the user's addresses). The reply format stays
`{ "clients": [...], "topics": [...] }`. Instructions: return exactly one client per client domain, named from the
domain and the conversation, reusing an existing client tag when it is the same company; only when there are no
client domains, identify clients from the title and transcript; never return the user's organization. Minutes then
enforces: at most two, never a tag whose slug matches an own-domain name. When the model fails, client domains are
still tagged from the domain itself (`drgreenlife.com` → `client/drgreenlife`).

### D4. Pending tagging and retry
The sidecar gains `tagging: { pending: Bool, lastError: String? }`. Saving a note with a provider configured sets
`pending = true`; a successful tagging sets `pending = false, lastError = nil`; a failure keeps `pending = true` and
stores `lastError`. At launch, after the index scan, notes whose sidecar is pending are tagged sequentially, once.
Manual Re-tag uses the same path. The meeting detail shows "Tagging failed: <lastError>" with Re-tag when
`lastError` is set. Errors are no longer swallowed in this path.

## Risks / Trade-offs

- [Vendors or guests with business addresses become clients] → the user's explicit rule; at most two by attendee
  count; tags are editable and manual edits survive re-tagging.
- [Old notes lack attendee emails when names were shown] → they fall back to the model with the title and
  transcript, with the domains of "Your email addresses" excluded.
- [A provider outage at launch retries many notes] → one sequential pass per launch, no loop.
