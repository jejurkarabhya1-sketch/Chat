# Veyra — Security and Production Release Gates

This repository is a development foundation, **not a certified production-ready messenger**. A real launch requires operational credentials, integration/device testing, and independent security review.

## Hardening added in this package
- Production configuration rejects the development JWT secret, missing Firebase project ID, SQLite, and plaintext messaging enabled.
- Plaintext message API can be disabled using `ALLOW_PLAINTEXT_MESSAGES=false`.
- Docker Compose no longer supplies a default database password.

## Mandatory before production
1. **Phone auth**: configure Firebase Phone Auth, verify ID-token exchange against real Firebase accounts, set quota/budget alerts, App Check where appropriate, abuse controls, and account recovery.
2. **Cryptography**: implement a vetted, supported end-to-end encryption protocol on clients; signed prekey lifecycle, one-time prekeys, device linking, key changes, safety-number/key verification, group sessions, replay protection, secure key storage, encrypted backups policy, and multi-device behavior. Do not design a custom cipher. Obtain independent security review.
3. **API security**: distributed rate limiting, request size limits, strict CORS, WebSocket origin/token protections, refresh-token rotation/revocation, device/session management, audit events without sensitive content, account deletion/export, and privacy policy.
4. **Data layer**: Review and test the included Alembic baseline and all future migrations, PostgreSQL backups and tested restore, retention/deletion policy, indexes, connection pool limits, encryption at rest, least-privilege DB credentials, and disaster recovery objectives.
5. **Messaging reliability**: durable queue/pub-sub (e.g. Redis or managed equivalent) for multi-instance WebSocket fanout, idempotency keys, offline delivery, acknowledgements, ordering strategy, retry policy, delivery/read receipts, and load tests.
6. **Media**: signed upload/download URLs, private object storage, size/type validation, malware scanning where appropriate, expiring access, metadata minimization, and client-side encryption before upload if content is E2EE.
7. **Push/calls**: FCM/APNs configuration, notification privacy, WebRTC, TURN, network/security testing, and permission UX.
8. **Mobile release**: Firebase Android config, signing keys stored securely, release build, crash reporting without message contents, accessibility checks, Android-version/device matrix, offline/poor-network testing, Play policy and privacy declarations.
9. **Operations**: HTTPS/WSS, secret manager/workload identity, metrics/logging/alerts, incident response, vulnerability scanning, dependency/license review, penetration testing, data-protection review, and support process.

## Production environment guardrails
Set `APP_ENV=production`, a unique random `JWT_SECRET` of at least 32 characters, `FIREBASE_PROJECT_ID`, a PostgreSQL `DATABASE_URL`, and `ALLOW_PLAINTEXT_MESSAGES=false`. The application refuses to start if these core production conditions are not met. Even when they are satisfied, production startup is deliberately blocked until a client-side E2EE protocol has been implemented and independently audited.

**Important limitation:** The current encrypted-message endpoint and public-key records are scaffolding. They are not a complete E2EE protocol. Do not expose the service publicly or claim end-to-end encryption until client encryption is implemented and audited.


## Scale readiness
The current in-process WebSocket manager is not multi-instance safe. Before public launch, implement a durable message/outbox pipeline, broker-backed fanout, distributed rate limiting, metrics/tracing, migrations, tested backups, and realistic load tests. Read `SCALABILITY_PLAN.md`. Do not claim million-user capacity without measured results.


## Delivery receipt security
Delivery retrieval is scoped to the authenticated recipient, acknowledgement endpoints reject non-recipient users, and message receipt queries are restricted to the sender. Delivery states only advance from pending to delivered to read. Idempotency keys are scoped by sender and protected by a database uniqueness constraint. Do not treat these checks as a substitute for full API penetration testing.

## Transactional notification outbox (implemented, not a distributed broker)
- Message creation writes per-recipient outbox events in the same transaction as the message and delivery records.
- A lifespan-managed dispatcher sends WebSocket hints and retries transient failures with bounded exponential backoff.
- A crash after socket delivery but before database commit may duplicate a hint; clients must deduplicate by message ID.
- Offline delivery must be recovered from durable delivery records. The current Flutter UI has not yet completed end-to-end inbox synchronization/acknowledgement integration.
- The dispatcher runs in each API process and cannot route to sockets connected to another process. Before horizontal scaling, replace/extend it with a shared broker or dedicated realtime gateway, metrics, and load/failover tests.

## HTTP abuse protection
A fixed-window HTTP rate limiter is included for authentication exchange, message submission, user search, and push-device registration. Redis-backed counters are shared across instances; local-memory fallback is not production-grade. Rate limits should be reviewed against telemetry and supplemented with per-account quotas, edge WAF/bot controls, request-size limits, and abuse reporting before public launch. `/health/live` and `/health/ready` separate liveness from dependency readiness.
