## Why

Real use with DeepSeek showed weak results that trace back to missing context rather than the model: Parakeet
transcribed "DrGreenlife" as "Doctor Grim", the tagger turned that into `client/doctor-grim`, and the rule "reuse an
existing client tag" then spread the wrong tag to the meeting whose title and attendee domains clearly said
DrGreenlife. Summaries were generic, missed decisions and owners, and repeated misheard names, partly because
reasoning is turned off for DeepSeek and the model sees only the transcript. The user also needs a way to correct a
meeting in plain words and have Minutes remember the correction.

## What Changes

- Client naming: the title and the attendees' email domains take precedence over the transcript; an existing tag is
  reused only when it names the same company.
- Every summary, title and tagging request carries the meeting context: title, attendees with domains, the user's
  organization, known client tags, the glossary and the meeting's instructions, with the warning that the transcript
  can misspell names.
- Summaries become concrete (figures, dates, owners, decisions); the built-in General type is restructured; when the
  provider supports reasoning, summaries use it (titles, tags and the connection test do not).
- New "Correct with instructions…" in the meeting detail: the model turns the user's instructions into word
  replacements that Minutes applies to the transcript, the instructions are saved with the meeting, and the summary
  and tags are regenerated.
- New glossary in Settings › Summaries: corrections are remembered, applied to new transcripts and sent as context.

## Capabilities

### New Capabilities
- `meeting-corrections`: per-meeting instructions and the glossary.

### Modified Capabilities
- `meeting-tags`: client naming precedence and misheard names.
- `meeting-summaries`: meeting context, concrete summaries, reasoning for summaries (added requirements).
- `app-shell`: Settings › Summaries lists the glossary.

## Impact

- Code: prompts (summary, title, tags), the provider client (reasoning per request), sidecar (instructions),
  glossary store, transcript replacement in note and sidecar, meeting detail sheet, Settings › Summaries.
- Notes: the transcript of a meeting changes only through the glossary at save time or explicit instructions.
- Cost and time: summaries with DeepSeek reasoning take longer and use more tokens.
