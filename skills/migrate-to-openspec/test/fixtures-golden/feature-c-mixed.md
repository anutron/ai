# Feature C — Mixed prose and scenarios

## Purpose

Feature C exists to keep daily check-in data and goal-tracking data in lockstep. Without it, users see stale goal progress when they open the dashboard the morning after a check-in but before the nightly batch job runs. The user-visible cost of staleness is small but persistent — every morning the dashboard "feels" wrong by a day until the user manually refreshes. This feature eliminates that staleness by running a small reconciler between the check-in writer and the goal-tracking store.

## Requirements

### Requirement: Reconciler architecture and event subscription

The reconciler SHALL subscribe to the `checkin.committed` event published by the check-in writer onto a local event bus. Each event carries a check-in id and a list of affected goal ids. On receipt, the reconciler MUST load each affected goal record, recompute its progress fields based on the new check-in, and write the updated record back to the goal-tracking store.

#### Scenario: reconciler updates affected goals

- **WHEN** a `checkin.committed` event affects two goals and the reconciler processes the event
- **THEN** both goals' progress fields are updated and persisted

### Requirement: Idempotent event handling

The reconciler MUST be idempotent. Replaying the same event SHALL yield the same final state, because the event bus is at-least-once.

#### Scenario: duplicate delivery yields the same state

- **WHEN** a `checkin.committed` event is delivered twice for the same check-in and the reconciler processes both deliveries
- **THEN** the final goal state is identical to a single delivery (idempotent)

### Requirement: Retry on transient errors and unrecoverable failure surfacing

If any goal fails to update, the reconciler SHALL retry the entire batch with exponential backoff up to three attempts. Unrecoverable failures (after exhausting retries) MUST be surfaced as a persistent banner in the dashboard until the user dismisses them.

#### Scenario: transient error is retried successfully

- **WHEN** the goal-tracking store returns a transient error on the first attempt and the reconciler retries
- **THEN** the second attempt succeeds and the goal is updated

#### Scenario: retries exhausted queues a dashboard banner

- **WHEN** the goal-tracking store returns errors on three consecutive attempts and the reconciler exhausts retries
- **THEN** an unrecoverable-failure banner is queued for the dashboard

## Notes

- Event-bus topic name is `airon.checkin.committed` and is configurable via `CHECKIN_EVENT_TOPIC`.
- Retry backoff schedule: 1s, 4s, 16s. Configured at `config/reconciler.yml`.
- The persistent dashboard banner uses the existing `notice` table; no new table required.
- Telemetry: each successful reconciliation emits a `reconciler.success` metric with a `goal_count` tag.
