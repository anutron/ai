# Feature A — pure prose

## Purpose

Feature A is a pure-prose legacy spec. It describes architectural intent without using Given/When/Then test cases. The migration tool must convert prose-only specs into structurally valid OpenSpec capability files even when there is no scenario shape to lift directly from the source.

The feature provides a passive ambient indicator that surfaces the system's current sync state to the user. The indicator never blocks, never demands action, and never escalates on its own. Its job is to be glanceable — present when sync is healthy, distinct when sync is degraded, silent when the user has paused syncing.

A secondary goal is calibration: over time, the indicator's color history should reflect actual sync health so the user develops a learned association between the visual and the underlying state. The indicator should not invent severity it has not observed.

## Behavior

The indicator polls the sync subsystem every 30 seconds. If the last successful sync was within the last 10 minutes, the indicator renders green. Between 10 and 60 minutes, amber. Beyond 60 minutes, red. While a sync is actively in flight, the indicator pulses regardless of the underlying color band.

If the sync subsystem reports an authentication error, the indicator turns red immediately and remains red until the user re-authenticates. Network errors do not change the color — they extend the time-since-last-success counter naturally and the color reflects that delay.

## Notes

- Polling interval is configurable via `SYNC_INDICATOR_POLL_SECONDS`. Default is 30.
- Color thresholds are configurable via `SYNC_INDICATOR_THRESHOLDS_MINUTES` (comma-separated, e.g., `10,60`).
- The indicator is rendered in the macOS menu bar via the LaunchAgent at `~/Library/LaunchAgents/com.airon.sync-indicator.plist`.
- Authentication errors are detected by inspecting the sync subsystem's last-error JSON for `kind == "auth"`.
