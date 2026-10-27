# Veyra — Million-User Scalability Plan

## First, define the target
"Millions of users" must be translated into measurable requirements. One million registered accounts is not the same as one million concurrent connections. Before production sizing, decide: monthly active users, peak concurrent sockets, peak messages/second, group size distribution, media storage/egress, delivery latency SLO, regions, RPO/RTO, retention, and budget. Capacity must be measured in load tests, not asserted from architecture diagrams.

## Current bottlenecks (must not be mistaken for million-user readiness)
- WebSocket connections remain process-local, but configured Redis Pub/Sub now provides cross-instance realtime hint fanout. Connection registry and broker behavior still need load/failover testing.
- Messages, per-recipient delivery rows, and notification outbox events are committed transactionally; a process-local dispatcher retries outbox publication. Redis Pub/Sub is not durable, so PostgreSQL inbox recovery remains authoritative and a durable shared queue/stream plus separate workers remain future work.
- SQLAlchemy `Base.metadata.create_all` is used at startup; production needs versioned migrations.
- Conversation membership and message history are currently basic and need query-plan review, pagination guarantees, and abuse controls.
- The encrypted-message route is a transport/storage scaffold, not a vetted E2EE implementation.
- No push-notification worker, media object storage, distributed rate limiter, observability stack, or production load-test suite is included.

## Target logical architecture
1. **Edge:** CDN + WAF + DDoS controls + TLS termination; API gateway with request size limits and per-IP/account/device throttling.
2. **Identity:** Firebase Phone Auth for phone verification; backend verifies Firebase ID tokens, applies account/device policies, and issues short-lived scoped access tokens. Add refresh/session revocation and abuse/risk controls before launch.
3. **Stateless API tier:** horizontally scaled API pods/containers; no per-user connection state as the source of truth. Keep REST for account/conversation operations.
4. **Realtime gateway tier:** separate WebSocket gateways with connection quotas, heartbeat, backpressure, graceful draining, and connection registry in a shared low-latency store. Use a broker for cross-instance fanout; never depend on in-process dictionaries.
5. **Durable message pipeline:** validate authorization, persist message envelope + idempotency key + outbox record transactionally, then publish outbox events to a durable broker. Workers perform fanout, push notifications, delivery receipts, retries, and dead-letter handling. Do not acknowledge durable acceptance before database commit.
6. **Storage:** PostgreSQL for identity, conversation metadata, and durable message metadata; partition message data by an evaluated conversation/time strategy when measured thresholds justify it. Consider logical sharding by conversation ID only after operational expertise and real load measurements. Use object storage + CDN for media; store only metadata and encrypted object references in relational records.
7. **Presence and ephemeral events:** Redis or equivalent for TTL-based presence, typing, and connection routing. These signals are ephemeral and must not be treated as durable message state.
8. **Notifications:** FCM/APNs workers consume durable events and send minimal notification payloads; notification text should not expose message content when privacy settings or E2EE apply.
9. **Search:** for E2EE chats, server-side full-text search cannot inspect message contents. Prefer client-side local search; make any opt-in cloud search explicit and separately designed.
10. **Security/crypto:** audited client-side protocol with per-device identity, prekeys, session ratchets, key verification, multi-device handling, group-key management, encrypted backups if supported, and secure key storage. The server stores ciphertext and public key material only. Key changes must be visible to users.
11. **Observability:** structured logs without message contents or secrets, metrics, traces, SLO dashboards, alerts, audit events, crash reporting with privacy controls, and runbooks.
12. **Operations:** multi-zone deployment, tested backups/restores, migrations, secrets manager, incident response, dependency/SBOM scanning, disaster recovery, staged rollout, and rollback.

## Suggested implementation stack (not a vendor commitment)
- Flutter client; Firebase Phone Authentication for phone verification.
- FastAPI for initial API services; split services only where scale/team boundaries justify it.
- Managed PostgreSQL for transactional data.
- Redis-compatible managed service for ephemeral state/rate limits/connection metadata.
- Kafka-compatible durable event stream (or managed queue with equivalent durability) for message fanout and background work.
- S3-compatible object storage and CDN for encrypted media.
- Kubernetes or managed container platform only when operational capability and traffic justify it; a managed platform may be better for the first release.

These are design candidates, not implemented dependencies in the current ZIP. Do not add every component before there is a measurable need.

## Scale-out implementation phases
### Phase A — reliable single-region MVP
- Fix API/client integration; add Alembic migrations, typed errors, request IDs, idempotent sends, pagination cursors, rate limits, block/report, device/session management, and integration tests.
- Replace process-local delivery assumptions with a durable outbox + broker adapter and a separately scalable WebSocket gateway.
- Implement audited E2EE in the clients before allowing real user conversations in production.
- Add object storage, push notifications, observability, backups, and incident runbooks.

### Phase B — controlled beta
- Load-test realistic chat, group fanout, reconnect storms, offline delivery, and media traffic.
- Test at 2x–3x expected peak beta load, with explicit latency/error targets and graceful degradation.
- Verify account enumeration resistance, SMS abuse controls, spam handling, data deletion, retention, and privacy disclosures.

### Phase C — millions of accounts / high concurrency
- Use real production telemetry to scale gateways, brokers, workers, database read paths, and media egress independently.
- Evaluate partitioning/sharding only from measured hotspots; introduce regional routing and data residency controls where required.
- Run chaos, failover, restore, and security exercises before major growth campaigns.

## Initial SLO candidates (confirm with product/business)
- Message acceptance availability: 99.9% monthly for MVP.
- Online recipient delivery: p95 under 1 second within the same region under defined load.
- No message loss after durable acceptance; retry and duplicate handling must be tested.
- Recovery point objective and recovery time objective explicitly agreed and restore-tested.

These are target candidates, not current measured performance.


## Implemented reliability increment (2026-10)
A database-backed per-recipient delivery table now records pending, delivered, and read state transactionally with message creation. The API supports pending delivery retrieval, recipient-only acknowledgements, sender-only receipt queries, and optional message idempotency keys to make request retries safe. This allows offline/reconnecting clients to recover from missed WebSocket notifications. It is not a replacement for a durable broker/outbox worker, distributed fanout, push notifications, or load testing.


## Implemented reliability increment — transactional notification outbox (2026-10)
- Message creation now writes per-recipient notification events in the same database transaction as the message and durable delivery records.
- An API-process dispatcher polls committed events, sends low-latency WebSocket hints, retries transient send failures with exponential backoff, and marks events dead after a bounded retry count.
- Delivery rows remain authoritative; reconnecting clients recover messages from `/inbox/deliveries`, so a recipient with no local socket does not block the outbox. Clients must deduplicate notifications by message ID because a crash between send and commit can produce a duplicate hint.
- This is a single-process outbox dispatcher, not distributed fanout. Multiple API replicas still need a shared broker/realtime gateway or broker-backed routing, and production worker separation, queue metrics, and load/failover tests remain required.


## Implemented reliability increment — shared Redis realtime fanout (2026-10)
- The outbox dispatcher can publish notification envelopes to a shared Redis Pub/Sub channel when `REDIS_URL` is configured. Each API instance subscribes and forwards events to its local WebSocket connections. Docker Compose includes a Redis service with persistent storage and health checks.
- Redis Pub/Sub is intentionally only a low-latency hint channel, not the durable queue: it can lose events while a subscriber is disconnected. PostgreSQL message/delivery records and `/inbox/deliveries` remain authoritative for reconnect recovery. Client deduplication by message ID remains required.
- The development fallback without Redis is single-process only. Production is still blocked until audited E2EE is implemented; multi-instance Redis fanout is not load-tested and is not a claim of million-user capacity. A durable shared queue/stream and separate worker/gateway deployment remain follow-up work.
