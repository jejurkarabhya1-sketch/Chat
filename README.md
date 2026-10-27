# Veyra — Messaging Platform Foundation

Veyra is an original messaging-platform concept designed around private communication, thoughtful UX, and a scale-out architecture. This repository is a **development foundation, not a production-ready service**. It must not be marketed as supporting millions of users or as end-to-end encrypted until the relevant systems are implemented, load-tested, and independently reviewed.

## Current foundation
- Flutter Android client with premium green/mint UI, Firebase Phone Authentication integration path, chat list, basic conversation UI, updates/calls placeholders, and settings.
- FastAPI API with Firebase ID-token verification, short-lived API tokens, PostgreSQL-compatible SQLAlchemy models, conversations, messages, WebSocket notifications, and public device-key storage scaffolding.
- Docker Compose for local API + PostgreSQL development.
- Security, scalability, feature roadmap, and Firebase setup documentation.

## Build workflow: Web + Android

The repository includes GitHub Actions workflows:

- `.github/workflows/build-clients.yml` runs backend tests, Flutter analysis/tests, and builds both the Web bundle and Android release APK. The resulting files are downloadable from the successful workflow run under **Artifacts**.
- `.github/workflows/deploy-web-pages.yml` is a manual, configuration-checked GitHub Pages deployment workflow. It refuses to deploy unless the required repository variables are set.

The original source intentionally does not commit generated Flutter platform boilerplate. Generate it once after installing Flutter stable:

```bash
cd mobile
flutter create --platforms=android,web --project-name=veyra_messenger .
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --release
```

Or run the repository-wide checks from the project root with `./scripts/verify-local.sh`. It requires Python 3.12+ and Flutter stable installed locally.

### Run the app locally

1. Install Python 3.12+, Flutter stable, and Android Studio/Android SDK if building Android locally.
2. Copy `.env.example` to `.env`; set unique local secrets. Do not commit `.env` or Firebase service-account JSON.
3. Configure Firebase by following `FIREBASE_SETUP.md`.
4. Start the backend from `backend/` using `python -m pip install -r requirements.txt` and `uvicorn app.main:app --reload`.
5. For Android emulator use `--dart-define=API_BASE_URL=http://10.0.2.2:8000`. For a browser on the same development machine use `--dart-define=API_BASE_URL=http://localhost:8000`. A physical Android device needs the host machine's reachable LAN address; a deployed app needs a public HTTPS API URL.
6. Run `flutter run` from `mobile/`.

### Deploy Web to GitHub Pages

In the GitHub repository, add these **Actions → Variables** (not secrets; Firebase web config is client-side configuration, not a service-account credential):

- `API_BASE_URL` — public HTTPS URL of the deployed Veyra API
- `FIREBASE_WEB_API_KEY`
- `FIREBASE_WEB_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_WEB_VAPID_KEY` (for Web push notifications)
- `FIREBASE_ANDROID_API_KEY` and `FIREBASE_ANDROID_APP_ID` (for configured Android APKs)

Then enable GitHub Pages with **GitHub Actions** as the build/deployment source and run **Actions → Deploy Veyra web to GitHub Pages → Run workflow**. Configure the backend's `CORS_ORIGINS` to include the exact Pages origin, and enable Phone sign-in in Firebase Authentication. If deploying to a custom domain, review the `--base-href` in the deployment workflow.

### Android Firebase configuration

Android compilation can run in CI without Firebase credentials, but phone OTP will not work until you configure Firebase. Add `mobile/android/app/google-services.json`, apply the Google Services Gradle plugin as described in `FIREBASE_SETUP.md`, register the app's SHA-1/SHA-256 fingerprints, and enable Phone sign-in. Never add a Firebase Admin service-account JSON file to the mobile app.

## Durable message delivery phase
The backend now writes one durable `message_deliveries` row per recipient in the same database transaction as each message. Clients can retrieve pending deliveries from `GET /inbox/deliveries`, acknowledge `delivered` or `read` using `POST /inbox/deliveries/{delivery_id}/ack`, and senders can query recipient status through `GET /conversations/{conversation_id}/messages/{message_id}/delivery-status`. The status transitions are monotonic (`pending` → `delivered` → `read`). Encrypted-message submission accepts an optional client-generated `idempotency_key` so retrying a timed-out request does not create a duplicate. WebSocket events are best-effort low-latency hints; durable delivery records are the recovery source of truth. This is a database-backed delivery foundation, not yet a distributed broker, push notification service, or proof of large-scale throughput.

Before using this on an existing database, deploy with the Alembic migration command (`alembic upgrade head`) before starting the API. The Docker image already applies migrations on startup; production deployment should use a single migration job rather than having every replica migrate concurrently.

## Production and scale
Read `SCALABILITY_PLAN.md` and `SECURITY_AND_RELEASE_PLAN.md` before deploying. The current WebSocket manager is process-local, the schema is created with `create_all`, and the current encrypted-message endpoint stores ciphertext-shaped payloads but does **not** implement a cryptographic protocol. These are known blockers. Production needs migrations, a durable event/outbox pipeline, distributed fanout, rate limits, observability, backups, load testing, and audited client-side E2EE.

## Brand
Working brand: **Veyra**. The name, domain, trademarks, company name, and app-store availability have not been cleared.

### Language preference
The Flutter client includes a **Settings → Language** screen for English, Marathi, Hindi, or the device's supported system language. The selection is stored using `shared_preferences` and applies to both Flutter Web and Android. The settings screen, bottom navigation, and Storage and data screen are localized; further screens can be localized incrementally as product copy is finalized.


## Additional implementation and release gates

The Storage and data screen now records approximate HTTP API payload bytes sent/received and request counts on-device, supports resetting those counters, clears Flutter's in-memory image cache, and saves a data-saver preference. Usage estimates exclude request/response headers, TLS overhead, and WebSocket traffic. Since chat media transfer is not implemented, the data-saver preference is persisted for future use but does not yet change media behavior.

The client also replaces deprecated `Color.withOpacity` calls with `withValues(alpha: ...)` and builds localized navigation labels without const-expression errors. Added widget tests cover storage usage counters and the persisted data-saver preference.

**Production safety gate:** the API now defaults to disabling plaintext messages, Docker Compose does the same, and the backend deliberately refuses to start with `APP_ENV=production` until a client-side end-to-end encryption protocol is implemented and independently audited. An initial Alembic migration is included and validated in CI. Push-device registration and generic Firebase Cloud Messaging notifications are now implemented, but require Firebase Admin credentials, Web VAPID setup, and real-device/browser validation. Media storage and load-test evidence remain outstanding. This is an intentional fail-closed gate, not a claim that production readiness has been achieved.


### Message delivery reliability
Message creation writes durable per-recipient delivery rows and notification-outbox events transactionally. The API dispatcher retries failed WebSocket hints with backoff. Offline clients must fetch pending deliveries from `/inbox/deliveries` and deduplicate by message ID. The dispatcher is currently process-local; it is not a distributed broker and must not be advertised as multi-instance fanout.


### Shared realtime fanout
Docker Compose starts Redis and configures `REDIS_URL=redis://redis:6379/0` for the API. The transactional outbox publishes notification hints to Redis Pub/Sub; each API instance fans out to its local WebSocket clients. Durable PostgreSQL inbox rows remain the recovery source because Pub/Sub can lose events during disconnects. Running without Redis is for single-process development only.


### Push notifications phase
The backend provides authenticated `POST /users/me/push-devices` and `DELETE /users/me/push-devices/{device_id}` endpoints. Migration `0004_push` adds the FCM device registry. Each message recipient gets a separate push outbox event, so FCM failures do not block realtime fanout. Push notifications intentionally show only a generic “New message” notice and do not include message contents or ciphertext. The Flutter client requests permission and registers/refreshes FCM tokens on Android and Web when configured; logout unregisters the device best-effort. See `FIREBASE_SETUP.md` for credentials, VAPID, service-worker and device-testing steps. Push is at-least-once and may duplicate; the durable inbox remains authoritative.

## Offline inbox recovery (latest phase)

The backend exposes `GET /inbox/sync?after_id=<delivery-id>&limit=100` for authenticated, cursor-based recovery. It returns delivery records including already-delivered/read rows, so a reinstall can recover acknowledged messages from the server rather than depending only on pending deliveries. The Flutter client stores a bounded per-conversation cache in `shared_preferences`, deduplicates by message ID, writes each page before acknowledging pending delivery records, and persists the cursor only after page processing succeeds. Repeated pages are safe to replay.

The client also caches the conversation list for temporary offline viewing, periodically syncs the inbox, and retries WebSocket connections after a disconnect. Cache is cleared when an online account check detects a different Veyra user. The current cache is bounded to 500 messages per conversation and is a recovery cache, not a full encrypted database or multi-device protocol. Production deployments still require a reviewed encrypted local store, actual client-side E2EE/decryption, integration tests on Android/Web, and handling for very large history pagination.

### Backup and restore

Open **Settings → Storage and data → Backup and restore** to create a passphrase-protected `.veyra` file or restore one. The backup is encrypted locally using AES-256-GCM with a PBKDF2-HMAC-SHA256-derived key. It includes only cached conversations/messages and selected preferences; it excludes authentication and push tokens and does not contain full server history, media, or private keys. Restore requires the same Veyra account and resets the inbox cursor so the client can resync from the durable server inbox. Keep the passphrase safe; it cannot be recovered.

### API abuse protection and readiness probes
The API now applies fixed-window request limits: Firebase token exchange (10/minute), encrypted/plaintext message submission (60/minute), user search (30/minute), push-device registration (20/minute), and a default 120/minute for other HTTP routes. Limits are keyed by the socket peer address and route group; the middleware deliberately does not trust client-supplied `X-Forwarded-For`. When Redis is configured, counters are shared across API instances. Without Redis, the fallback is process-local for development/tests only and does not protect a multi-instance deployment. `429` responses include `Retry-After`; `/health/live` is a liveness probe and `/health/ready` checks the database and configured Redis dependency.
