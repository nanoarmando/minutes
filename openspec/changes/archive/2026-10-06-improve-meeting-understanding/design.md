## Context

Tagging already builds a header with title, client domains and the user's organization (`ClientDomains`,
`TagService`). Summaries and titles send only the transcript plus the summary-type instructions. `ChatClient` turns
DeepSeek thinking off for every request. The sidecar holds segments, summary metadata, manual tags, `event` and
`tagging`.

## Goals / Non-Goals

**Goals:** one shared meeting-context block for every model request; reliable client names; concrete summaries;
user corrections that persist.
**Non-Goals:** speech-model vocabulary biasing (Parakeet has no supported hook in FluidAudio 0.15.5); letting the model
rewrite whole transcripts.

## Decisions

### D1. One meeting-context builder
`MeetingContext` (Summaries/) builds a short block from the sidecar `event` (else front matter title and attendees),
`ClientDomains`, the known client tags from `NoteIndex`, the glossary and the meeting's `instructions`:
```
Meeting title: DrGreenlife - Followup
Attendees: Ryan (drgreenlife.com), Anthony (drgreenlife.com), Pablo Veliz, Paula Borrelli (vnstudios.com)
User's organization: vnstudios.com
Known clients: client/drgreenlife, client/acme-retail
Glossary: Doctor Grim → DrGreenlife; Pablo Belis → Pablo Veliz
Instructions from the user: Pablo Veliz works at VNS.
Note: the transcript is automatic and can misspell names; write names as they appear above.
```
Empty lines are omitted. Summary, title and tag requests put it before the transcript. One builder keeps the three
prompts consistent (DRY).

### D2. Client naming precedence
The tag prompt says: name each client domain by comparing it with the meeting title (title spelling wins over the
domain's, e.g. "DrGreenlife" over "drgreenlife"); reuse an existing client tag only if it names the same company as
that evidence. Swift guards: for each client domain, if the model's tag shares no token with the domain label or the
title words (compared lowercased with hyphens removed), the domain-derived tag is used instead.

### D3. Reasoning per request
`ChatClient.complete` gains `reasoning: Bool` (default false). For api.deepseek.com, `thinking` is `enabled` (with
`reasoning_effort: "medium"`, chosen by the user over the default "high") when true and `disabled` otherwise; summaries pass true with `max_tokens` 16,000 and a 300 s timeout; titles, tags and the test
pass false. Other providers ignore the flag (no portable parameter); `<think>` stripping stays.

### D4. Concrete summaries and General
The base instruction adds: report figures, prices, estimates, dates and deadlines as stated; attribute commitments
and opinions to people by name; decisions with reasons; action items as "- [ ] Owner: task (due)"; no generic
filler; say "None" for an empty section. General becomes: Context · Key points · Decisions · Action items · Risks and
open questions. Users who edited General keep their override.

### D5. Instructions and glossary
- Sidecar gains `instructions: String?`. The detail does not display them (they read as noise next to the note);
  reopening the sheet pre-fills them.
- "Correct with instructions…" opens a sheet with a text field. Apply → one model call returning
  `{"replacements": [{"from": "...", "to": "..."}]}` from the instructions plus the transcript's distinct capitalized
  words and the context (bounded excerpt), so the model only maps words that exist. Minutes applies them
  directly, with no confirmation step (the user found the list confusing), as whole-word, case-insensitive replacements to the Markdown transcript section
  and the sidecar segments (atomic writes, summary markers untouched), merges them into the glossary, stores the
  instructions, then regenerates the summary (current type) and re-tags.
- Glossary: `~/Library/Application Support/Minutes/glossary.json`, `[{from, to}]`, edited in Settings › Summaries
  (add, edit, delete). Applied to the assembled transcript before the note is first written; never retroactively.
- `NotesDictionary` lists the glossary so agents read names correctly too.

## Risks / Trade-offs

- [A replacement like "Grim" → "Greenlife" could hit unrelated words] → whole-word matching, only words present
  in the transcript, and the model is asked for multi-word phrases; glossary entries can be deleted in Settings.
- [Reasoning makes summaries slower and costlier] → only summaries use it; titles and tags stay fast.
- [The context block costs tokens] → it is a few lines; attendees are capped at 20.
