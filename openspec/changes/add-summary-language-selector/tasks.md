## 1. Language model and storage

- [x] 1.1 Sidecar field `language` (`en`, `es`, absent for Auto) with a write path that sets or clears it
- [x] 1.2 `MeetingLanguage` from a stored code, and one resolution used by summaries, corrections and tags
- [x] 1.3 Remove on-device detection (`NLLanguageRecognizer`); Auto asks the model for the language most of the
      transcript is spoken in, even though the instructions are in English (summaries, titles, topic tags)

## 2. Requests

- [x] 2.1 Summary regeneration, correction and re-tag pass the resolved language instead of detecting on their own

## 3. Meeting detail

- [x] 3.1 Language menu (Auto, English, Español) next to Regenerate, showing the stored choice, disabled while busy
- [x] 3.2 Choosing a language stores it, regenerates the summary with the current type, then re-tags; errors keep the
      previous summary and tags and are shown

## 4. Docs

- [x] 4.1 Update README and AGENTS.md (no detection, model judges in Auto, sidecar `language`, Language menu)
