# Feature C — mixed prose and scenarios

## Why this exists

Feature C exists to keep daily check-in data and goal-tracking data in lockstep. Without it, users see stale goal progress when they open the dashboard the morning after a check-in but before the nightly batch job runs. The user-visible cost of staleness is small but persistent — every morning the dashboard "feels" wrong by a day until the user manually refreshes. This feature eliminates that staleness.

## Architecture

The feature runs as a small reconciler that sits between the check-in writer and the goal-tracking store. When a check-in is committed, the writer fires an event onto a local event bus. The reconciler subscribes to those events, reads the affected goal record, recomputes derived progress fields, and writes the updated record back.

The reconciler is intentionally idempotent — replaying the same event yields the same final state — because the event bus is at-least-once. Failures are retried with exponential backoff up to three attempts; unrecoverable failures are surfaced as a persistent banner in the dashboard until the user dismisses them.

## Behavior

The reconciler subscribes to the `checkin.committed` event. Each event carries a check-in id and a list of affected goal ids. On receipt, the reconciler loads each goal, recomputes its progress fields based on the new check-in, and writes the result. If any goal fails to update, the entire batch is retried.

## Test cases

### Happy path

- **Given** a `checkin.committed` event affects two goals
  **When** the reconciler processes the event
  **Then** both goals' progress fields are updated and persisted

- **Given** a `checkin.committed` event is delivered twice for the same check-in
  **When** the reconciler processes both deliveries
  **Then** the final goal state is identical to a single delivery (idempotent)

### Failure handling

- **Given** the goal-tracking store returns a transient error on the first attempt
  **When** the reconciler retries
  **Then** the second attempt succeeds and the goal is updated

- **Given** the goal-tracking store returns errors on three consecutive attempts
  **When** the reconciler exhausts retries
  **Then** an unrecoverable-failure banner is queued for the dashboard

## Notes

- Event-bus topic name is `airon.checkin.committed` and is configurable via `CHECKIN_EVENT_TOPIC`.
- Retry backoff schedule: 1s, 4s, 16s. Configured at `config/reconciler.yml`.
- The persistent dashboard banner uses the existing `notice` table; no new table required.
- Telemetry: each successful reconciliation emits a `reconciler.success` metric with a `goal_count` tag.
