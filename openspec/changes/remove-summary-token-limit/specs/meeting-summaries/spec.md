## MODIFIED Requirements

### Requirement: Reasoning for summaries
When the provider offers a reasoning mode, summaries SHALL use it at medium effort. Summary requests SHALL NOT set an
output token limit, so the provider's own maximum applies to the reasoning and the answer; titles, tags,
corrections and the connection test SHALL NOT use reasoning and SHALL keep their own limits.

#### Scenario: DeepSeek summary
- **WHEN** the summary provider is DeepSeek and a meeting is summarized
- **THEN** the request enables thinking at medium effort, while the title and tagging requests for the same meeting do not

#### Scenario: Long reasoning
- **WHEN** the model reasons for more than 16,000 tokens before writing the summary
- **THEN** the summary is still written, because the request sets no output token limit
