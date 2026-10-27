# Veyra — Product Roadmap and Engagement Features

## Core first (trust before novelty)
- Reliable 1:1 and group messaging, reply/quote, reactions, edit/delete, pin, search, drafts, offline queue, delivery/read states, multi-device sessions, and message sync.
- E2EE with key-change alerts, verified safety numbers/QR, secure device linking, and optional encrypted backups only after a reviewed design.
- Block, report, anti-spam controls, group invite permissions, disappearing messages, privacy controls for profile/photo/last-seen/online state, and account deletion/export.
- Accessibility, low-data mode, local-language UI, and support for older Android devices.

## Differentiators for the next generation
1. **Private AI assistant:** optional on-device summaries, voice-note transcription, translation, and suggested replies. Make cloud AI opt-in, explain what data leaves the device, and do not silently send E2EE content to a server model.
2. **Live translation:** translate on-device where feasible; clearly distinguish original and translated text.
3. **Communities and channels:** announcement channels, topic-based groups, admin roles, moderation queues, invite links, slow mode, and spam-resistant joining.
4. **Voice-first experience:** high-quality voice notes, transcript on request, playback speed, noise reduction, and accessible controls.
5. **Lightweight sharing:** secure file/photo/video sharing with resumable uploads, compression controls, expiry options, and user-visible storage limits.
6. **Events and coordination:** polls, RSVP, shared calendars, pinned plans, and location sharing with a clear timeout.
7. **Creator and business tools:** verified official accounts, opt-in broadcast lists, catalog/booking integrations, and transparent business labels; avoid unsolicited mass messaging.
8. **Trust center:** active devices, key verification, privacy dashboard, security notices, account export/delete, and abuse-report status.
9. **Cross-device continuity:** safe device linking and synced settings; encrypted message synchronization must be designed with the E2EE protocol.
10. **Community safety:** user-controlled message requests, new-account rate limits, group invite controls, scam warnings, and human escalation for serious reports.

## Engagement without manipulation
- User-controlled notification categories and quiet hours.
- Digest options for noisy groups, mute-until, and per-chat notification controls.
- No streaks, fake urgency, or dark patterns designed to increase compulsive use.
- Measure meaningful outcomes: successful conversations, user-reported usefulness, retention by cohort, safety incidents, delivery reliability, and opt-out rates—not only time spent.

## Monetization options to evaluate later
- Optional premium themes, extra encrypted storage/backup capacity, and productivity tools.
- Business subscriptions for verified support inboxes, team roles, and opt-in customer messaging.
- Paid community/creator tools where local law and platform policies allow.
- Keep core private messaging accessible and never sell private message contents or contact graphs.

## Release order
1. Security and reliability foundation.
2. Small closed beta with real device testing and abuse reporting.
3. Media, push, offline delivery, and device management.
4. Communities and channels.
5. Optional privacy-preserving AI and translation.
6. Calls, business features, and monetization after quality gates are met.


## Implemented foundation phase — push notifications (2026-10-26)
- Added authenticated FCM token registration and per-device unregister endpoints.
- Added Alembic migration `0004_push` for device token registry.
- Added separate transactional outbox events for push notifications so FCM failures do not block realtime fanout.
- Push payloads are generic and contain no message text or ciphertext. Invalid/unregistered FCM tokens are deactivated.
- Flutter now requests notification permission and registers/refreshes tokens on Web and Android where configured; logout unregisters the device best-effort.
- Remaining: Firebase project credentials and VAPID setup, real-device/browser testing, notification deep-link routing, operational metrics/alerting, and production-scale load testing.
