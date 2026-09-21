# Composer controls validation — 2026-09-20

Version: 0.3.23 (26).

- Official reference: https://learn.chatgpt.com/docs/app-server (turn/interrupt, turn/steer, thread/goal/set).
- Installed protocol: .local/hook-verification/schema/v2 (thread/queue/add, list, start, delete; no atomic queue-to-steer operation).
- Live disposable probe: ComposerQueueLiveProbe. Thread 01a0bf2c-2d75-7311-bf64-b3bf0395e860. Queue add, turn/steer with expected turn ID, acknowledged queue deletion, confirmed stop all passed. No user sessions used.
- Deterministic tests cover steering success, rejection, uncertain delivery, failed deletion, Goal/Plan exclusion, one-turn goal submission and stop pausing goals.
- Visual inspection: idle and active composers at 520 and 800 points. Controls wrap at narrow widths.

Queue promotion preserves raw provider input, including attachments. Auto-delivery pauses during promotion; uncertainty retains queue recovery markers across restarts. The UI keeps the Stop square available and exposes a separate Queue message action while working. Stop returns to Send only on a provider terminal event.

Goal is off by default; enabling it uses the next message as the objective. A paused goal is configured before the message is sent, then activated after send acknowledgement. Activation failure reports that the message was sent, avoiding a resend. Turning Goal off or choosing Plan pauses an existing active goal on the next normal send. New goal activation sequence is covered by transport tests, not a live goal probe in this batch.
