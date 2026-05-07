# Feature D — unbuilt change candidate

## Purpose

Feature D describes future behavior that has not been implemented. It exists as a legacy spec alongside a matching plan under `specs/plans/`, and the migration tool must route it to `openspec/changes/<change-name>/` rather than `openspec/specs/<capability>/spec.md`.

## Requirements

### Requirement: Daily digest delivery

The system SHALL deliver one digest email per recipient per day at the recipient's configured local-time slot. The digest MUST include every event published to that recipient's subscription channels during the prior 24 hours.

#### Scenario: digest delivered at the configured time

- **GIVEN** a recipient configured for 09:00 local digest delivery
- **WHEN** the daily scheduler ticks past 09:00 in the recipient's timezone
- **THEN** the digest email is queued for delivery within 60 seconds

#### Scenario: digest skipped on quiet days

- **GIVEN** a recipient with no events in the prior 24-hour window
- **WHEN** the daily scheduler ticks past their delivery slot
- **THEN** no email is queued and a "no-events" log line is written

### Requirement: Recipient digest preferences

The system SHALL expose a settings endpoint that lets recipients configure their delivery slot (one of 06:00, 09:00, 12:00, 18:00 local time) and toggle the digest on or off entirely. Updates MUST take effect on the next scheduler tick.

#### Scenario: recipient changes delivery slot

- **GIVEN** a recipient with delivery slot set to 09:00
- **WHEN** the recipient submits a settings update changing the slot to 18:00
- **THEN** subsequent digests are queued for the 18:00 slot in their timezone
