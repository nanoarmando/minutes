## MODIFIED Requirements

### Requirement: Automatic client detection
When "Detect clients automatically" is on and a summary provider is configured, Minutes SHALL tag the meeting with
at most two client tags of the form "client/" followed by the lowercase, hyphenated client name, determined as
follows:
- The user's address in the meeting SHALL be the attendee address that matches one of "Your email addresses",
  else the address the calendar marks as the user's. The user's organization for the meeting SHALL be that
  address's domain. When it cannot be known (no calendar event, no user address in it, or a note re-tagged without
  event data), the domain of every address in "Your email addresses" SHALL count as the user's organization.
- Every attendee email domain that is neither the user's organization nor a personal email domain (such as
  gmail.com, outlook.com or icloud.com) SHALL be a client of the meeting. Attendees whose address is one of "Your
  email addresses" SHALL be ignored. The domains of the user's other addresses SHALL count as clients when the user
  attends with a different organization's address.
- Minutes SHALL ask the summary model to name each client by comparing the meeting title with the client
  domains of the attendees (for example "DrGreenlife - Followup" and `drgreenlife.com` → "DrGreenlife"). The title
  and the attendee domains SHALL take precedence over the transcript, whose automatic transcription can misspell
  names. An existing client tag SHALL be reused only when it names the same company as the title or the domain;
  a tag spelled differently from that evidence SHALL NOT replace it. When the meeting has no client domains, the
  model SHALL identify clients from the meeting title and transcript, using the glossary and the known client tags
  to correct misheard names.
- The user's organization SHALL never become a client tag; internal meetings SHALL get no client tag. When there
  are more than two client domains, the two with the most attendees SHALL be kept.

#### Scenario: Client call
- **WHEN** a meeting is a call with Hemisphere Brands and no client tags exist yet
- **THEN** the note is tagged "client/hemisphere-brands"

#### Scenario: Client named only in the calendar event
- **WHEN** the transcript never names the client, and two attendees of the event use `@drgreenlife.com`
- **THEN** the note is tagged "client/drgreenlife"

#### Scenario: A misspelled tag does not win over the domain
- **WHEN** the tag "client/doctor-grim" exists from a misheard transcript, and a meeting titled "DrGreenlife - Followup" has attendees at `@drgreenlife.com`
- **THEN** the meeting is tagged "client/drgreenlife", not "client/doctor-grim"

#### Scenario: Misheard name without attendees
- **WHEN** a meeting without client attendees says "Doctor Grim", and "client/drgreenlife" exists or the glossary maps "Doctor Grim" to "DrGreenlife"
- **THEN** the meeting is tagged "client/drgreenlife"

#### Scenario: Own organization depends on the account
- **WHEN** "Your email addresses" lists jose.bianco@vnstudios.com and jose@tvp.com, the user joins the event as jose.bianco@vnstudios.com and the other attendees use `@tvp.com`
- **THEN** the note is tagged "client/tvp" and never "client/vn-studios"

#### Scenario: Colleague from the same organization
- **WHEN** a colleague with the same email domain as the user attends a client call
- **THEN** the colleague's organization is not tagged as a client

#### Scenario: Unknown account
- **WHEN** a meeting has no calendar event and its transcript discusses Acme Retail as a client
- **THEN** the note is tagged "client/acme-retail", and no domain of "Your email addresses" is tagged

#### Scenario: Personal email guest
- **WHEN** an attendee uses a gmail.com address
- **THEN** no client tag comes from that attendee

#### Scenario: Same client, different wording
- **WHEN** "client/hemisphere-brands" already exists and a later meeting with `@hemispherebrands.com` attendees is tagged
- **THEN** the note is tagged "client/hemisphere-brands", not a new client tag

#### Scenario: Internal meeting
- **WHEN** every attendee shares the user's domain and the transcript names no external client
- **THEN** the note has no client tag
