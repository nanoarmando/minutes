## Why

Summary requests send `max_tokens: 16000`. With DeepSeek's reasoning mode the hidden reasoning counts against that
limit, and on 2026-10-06 the meeting "DrGreenMom - Revamp" spent all of it reasoning, so no summary was written
("The model used its whole token budget before answering").

## What Changes

- Summary requests no longer send an output token limit; the provider's own maximum applies.
- Titles, tags, corrections and the connection test keep their small limits (they run without reasoning).

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `meeting-summaries`: the reasoning requirement no longer sets a token budget for summaries.

## Impact

- Code: the summary call in `SummaryService` and the optional limit in `ChatClient`.
- Cost per summary is no longer capped by Minutes; it is bounded by the provider's maximum and the 300 s timeout.
