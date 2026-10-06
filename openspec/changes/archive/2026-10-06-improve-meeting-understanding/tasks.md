## 1. Context and naming

- [x] 1.1 Add `MeetingContext` (title, attendees with domains, user's organization, known clients, glossary,
      instructions, misspelling note) and use it in summary, title and tag requests
- [x] 1.2 Client naming precedence in the tag prompt and the Swift guard against tags unrelated to the domain/title

## 2. Summaries

- [x] 2.1 `reasoning` flag in `ChatClient` (DeepSeek thinking on for summaries with a 16k budget, off elsewhere)
- [x] 2.2 Concrete base instructions and the new General structure

## 3. Corrections

- [x] 3.1 Glossary store, Settings › Summaries editor, applied to new transcripts before the first write, listed in
      the notes dictionary
- [x] 3.2 Sidecar `instructions`; shown and editable in the meeting detail; sent as context on regenerate and re-tag
- [x] 3.3 "Correct with instructions…" sheet: replacements call, preview, apply to note and sidecar, merge into
      glossary, regenerate summary and re-tag, error state

## 4. Adjustments after first use

- [x] 4.1 DeepSeek summaries use `reasoning_effort: "medium"`
- [x] 4.2 Remove the instructions display from the meeting detail; the sheet pre-fills saved instructions
- [x] 4.3 Apply corrections in one step: no replacements preview or Confirm, progress only

## 5. Docs

- [x] 5.1 Update README and AGENTS.md
