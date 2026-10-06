## Context

`ChatClient.complete(maxTokens: Int = 2500, …)` always sends `max_tokens` (`max_completion_tokens` on
api.openai.com). `SummaryService.summarize` passes 16,000 with reasoning on.

## Goals / Non-Goals

**Goals:** summary requests carry no output limit.

**Non-Goals:** changing the 300 s timeout, retries, or the limits of titles, tags, corrections and the connection
test.

## Decisions

- `maxTokens` becomes `Int?`; when nil the token key is omitted from the body. Other callers keep their values; the
  default stays 2500 so only the summary call changes (it passes nil).
- The "out of tokens" error stays: a provider can still stop at its own maximum.

## Risks / Trade-offs

- [Long reasoning can hit the 300 s timeout] → the request fails with the existing timeout error and is retried as
  today; the note keeps the transcript and can be regenerated.
- [Higher cost when the model reasons at length] → accepted by the user; bounded by the provider's maximum.
