## 1. Data

- [x] 1.1 Add `attendeeEmails` and `ownDomain` to `EventInfo` in the calendar lookup (current-user domain, calendar
      source email fallback) and keep front matter `attendees` unchanged
- [x] 1.2 Add the sidecar fields `event` and `tagging { pending, lastError }`, backward compatible
- [x] 1.3 Add the `userEmails` preference and the "Your email addresses" field in Settings › Tags

## 2. Client detection

- [x] 2.1 Domain rules: user's address from `userEmails` matching the attendees (else current user, else calendar
      account), normalization, personal-domain list, own set (that domain, else all `userEmails` domains), client
      domains ordered by attendee count, at most two
- [x] 2.2 Tagging header (title, client domains, user's organization) and prompt update; enforce rules on the reply
      and fall back to domain-derived tags when the model fails
- [x] 2.3 Use the sidecar event, else front matter title and attendees, for re-tag and re-tag all

## 3. Reliability

- [x] 3.1 Mark notes pending on save, clear on success, store the error on failure (no swallowed errors)
- [x] 3.2 Retry pending notes once at launch, sequentially
- [x] 3.3 Show "Tagging failed" with the reason and Re-tag in the meeting detail

## 4. Docs

- [x] 4.1 Update README and AGENTS.md (client rules, "Your email addresses", sidecar fields, retry)
