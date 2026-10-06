## Context

`MeetingLanguage` detected the transcript language with `NLLanguageRecognizer` and named it in the summary, title and
tag prompts. Detection on the note's transcript section included the `**[HH:MM:SS] Speaker:**` prefixes, which made a
Spanish transcript read as Polish (0.99). Even with a correct explicit "Spanish" instruction, DeepSeek with reasoning
once answered in English, because every other part of the prompt is in English. The language instruction is now
placed both before and after the transcript.

## Goals / Non-Goals

**Goals:**
- No on-device language detection; the model judges the language in Auto.
- Per-meeting override (Auto, English, Español) that drives summaries, corrections, titles and topic tags.
- One action: choosing a language regenerates the summary and re-tags.

**Non-Goals:**
- A global language setting or a language for new recordings.
- Changing the transcription language or re-transcribing.
- Regenerating or translating the title from the menu.
- Languages other than English and Spanish.

## Decisions

- **Auto instruction:** "Write the whole summary, including the section headings, in the language most of the
  transcript is spoken in, even though these instructions are in English." Titles and topic tags use the same
  phrase ("in the language most of the transcript is spoken in"). The explicit "even though these instructions are
  in English" counters the pull of the English prompt.
- **Chosen instruction:** names the language ("in Spanish (es) … Do not write any part of the answer in another
  language.").
- **Storage:** sidecar field `language` (`"en"` or `"es"`, absent for Auto), next to `instructions`. The note format
  does not change. Alternative (front matter key) rejected: it changes the note contract for a processing preference.
- **Resolution:** `MeetingLanguage` is built only from a stored code; `MeetingContext.language` returns it or nil
  (Auto). `NLLanguageRecognizer` and the `NaturalLanguage` import are removed.
- **Flow:** the detail view stores the choice in the sidecar first, then runs the existing regenerate path with the
  current summary type, then the existing re-tag path only if the summary succeeded.
- **UI:** a `Menu` labelled "Language: Auto" (or English / Español) between the type chips and Regenerate, disabled
  while regenerating or re-tagging.

## Risks / Trade-offs

- [In Auto the model can still answer in English] → the instruction names the risk explicitly and sits before and
  after the transcript; the Language menu fixes a single meeting in one step.
- [Re-tag after a language change replaces automatic tags] → same behavior as Re-tag today; manual tags are kept.
- [Sidecar deleted] → the meeting falls back to Auto, consistent with the rule that notes work without sidecars.
