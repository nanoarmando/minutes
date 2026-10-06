## MODIFIED Requirements

### Requirement: Tag settings
Settings SHALL have a Tags section with the switches "Detect clients automatically" and "Add topic tags
automatically", both on by default, a "Your email addresses" field where the user lists the addresses they join
meetings with (for example `jose.bianco@vnstudios.com, jose@tvp.com`), empty by default, and a "Re-tag all
meetings" action. It SHALL NOT offer any client list or client editor.

#### Scenario: Open Tags settings
- **WHEN** the user opens Settings › Tags
- **THEN** the two switches, the "Your email addresses" field and "Re-tag all meetings" are shown, and there is no way to add clients by hand

#### Scenario: Enter email addresses
- **WHEN** the user types "jose.bianco@vnstudios.com, jose@tvp.com" in "Your email addresses"
- **THEN** both addresses are saved and used by the next tagging

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
- Minutes SHALL ask the summary model to name each client domain, reusing an existing client tag of the notes
  folder when it is the same client, and, when the meeting has no client domains, to identify clients from the
  meeting title and transcript.
- The user's organization SHALL never become a client tag; internal meetings SHALL get no client tag. When there
  are more than two client domains, the two with the most attendees SHALL be kept.

#### Scenario: Client call
- **WHEN** a meeting is a call with Hemisphere Brands and no client tags exist yet
- **THEN** the note is tagged "client/hemisphere-brands"

#### Scenario: Client named only in the calendar event
- **WHEN** the transcript never names the client, and two attendees of the event use `@drgreenlife.com`
- **THEN** the note is tagged "client/drgreenlife"

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

### Requirement: Tagging runs after saving
Automatic tagging SHALL run with one model call after the note is saved, for every meeting when a provider is
configured, even when automatic summaries are off, and SHALL NOT delay saving the note. A note SHALL stay marked
as pending tagging until a tagging attempt succeeds. When the tagging call fails, or Minutes quits before it
finishes, Minutes SHALL retry pending notes at the next launch, once per launch. While a note's last attempt
failed, its detail in the Meetings window SHALL show "Tagging failed" with the reason and a Re-tag button. When no
provider is configured, the note keeps no automatic tags and is not marked pending.

#### Scenario: No provider
- **WHEN** no summary provider is configured
- **THEN** the note is saved without automatic tags and is not marked pending

#### Scenario: App quits during tagging
- **WHEN** Minutes quits right after saving a note, before tagging finishes
- **THEN** the note is tagged at the next launch without user action

#### Scenario: Provider error
- **WHEN** the tagging call fails with a provider error
- **THEN** the meeting detail shows "Tagging failed" with the error and a Re-tag button, and the note is retried at the next launch
