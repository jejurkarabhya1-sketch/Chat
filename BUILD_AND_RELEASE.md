# Veyra build and release runbook

This runbook targets the build failures encountered in earlier Flutter projects: absent Android/Web platform folders, missing Flutter SDK, web-incompatible assumptions, Firebase initialization errors, wrong API URLs, and GitHub Pages deployment configuration.

## 1. Toolchain

- Install the current Flutter stable SDK and use the Dart SDK bundled with it.
- For Android APK builds, install Android Studio / Android SDK and accept Android SDK licenses (`flutter doctor --android-licenses`).
- Install Python 3.12+ for backend tests.
- Run `flutter doctor -v` and resolve missing Android toolchain components before building locally.

## 2. Generate missing platform folders

The source repository intentionally keeps Flutter-generated platform boilerplate out of the starter archive. From `mobile/`, run:

```bash
flutter create --platforms=android,web --project-name=veyra_messenger .
flutter pub get
```

The CI workflows run this generation step automatically when either `mobile/android/` or `mobile/web/` is missing.
The Android workflow configures compile SDK 36 for the app and Android plugin modules. This is separate from target SDK and minimum SDK and is required by current AndroidX plugin dependencies.

## 3. Validate in the same order as CI

From the repository root:

```bash
# Backend
python -m pip install -r backend/requirements.txt
python -m compileall -q backend/app backend/migrations
cd backend
alembic upgrade head
alembic check
python -m pytest app -q
cd ../mobile

# Flutter
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --release
```

Use `scripts/verify-local.ps1` on Windows PowerShell or `scripts/verify-local.sh` on macOS/Linux to run the same checks as a single command.

## 4. Firebase requirements are runtime configuration, not compile requirements

The clients can compile without Firebase credentials so CI can validate the code. OTP will not work until Firebase is configured:

- Android: add `mobile/android/app/google-services.json`, apply the Google Services Gradle plugin to the generated Android project, register the exact Android application ID and SHA fingerprints in Firebase, and enable Phone sign-in.
- Web: pass the six documented `--dart-define` values from `FIREBASE_SETUP.md`.
- Backend: configure `FIREBASE_PROJECT_ID` and server-side Application Default Credentials / service-account credentials outside the mobile client.

Never commit service-account keys. Do not confuse successful compilation with successful OTP delivery.

## 5. API and Web deployment

- Android emulator: `--dart-define=API_BASE_URL=http://10.0.2.2:8000`.
- Browser on the same computer as the API: `--dart-define=API_BASE_URL=http://localhost:8000`.
- Physical device: use an API address reachable from that device.
- Public deployment: use a public HTTPS API URL, configure backend `CORS_ORIGINS` for the exact deployed site origin, and allow the deployed domain in Firebase Authentication.

The standard CI workflow builds artifacts for verification; those artifacts use development defaults and are not automatically production-configured. The separate Pages workflow requires repository variables and builds the Web app with the supplied API/Firebase configuration.

## 6. Download build artifacts from GitHub Actions

1. Push the repository to GitHub with its default branch named `main` or `master`.
2. Open **Actions → Build Veyra clients** and wait for all jobs to pass.
3. Download `veyra-web-<commit>` for the static Web bundle or `veyra-android-apk-<commit>` for the APK.
4. For Pages deployment, configure the repository variables listed in `README.md`, enable Pages with **GitHub Actions** as source, then manually run **Deploy Veyra web to GitHub Pages**.

## 7. Storage and data settings

The app records approximate API request/response body bytes and request counts locally, supports resetting those counters, clears Flutter in-memory image cache, and persists the data-saver preference. Counters exclude HTTP headers, TLS overhead, and WebSocket traffic. Media auto-download and media storage are not implemented, so the saved data-saver preference does not yet affect media transfers.

## 8. Release gate

Before a public release, additionally test OTP on real Android devices and supported browsers, backend authorization and CORS, WebSocket reconnect behavior, signed Android builds, database migrations/backups, rate limits, monitoring, and load tests. Veyra's current messaging and encryption components are still a development foundation; end-to-end encryption is not implemented or audited, and million-user capacity has not been demonstrated. The backend deliberately blocks `APP_ENV=production` until audited client-side E2EE exists. Plaintext messaging is disabled by default; only explicitly configured local development environments should enable it for temporary demos.


## Push notifications release checklist
- [ ] Add `FIREBASE_WEB_VAPID_KEY` as a GitHub Actions variable for Web builds.
- [ ] Configure the Firebase Web service worker (`mobile/web/firebase-messaging-sw.js`) for local builds; CI substitutes public web config when all required variables exist.
- [ ] Configure Firebase Admin Application Default Credentials on the backend host, not in the mobile client.
- [ ] Run `alembic upgrade head` and confirm `push_devices` exists.
- [ ] Test permission denied, token refresh, logout unregister, invalid token cleanup, foreground/background notifications, and notification clicks on actual Android devices and supported HTTPS browsers.
- [ ] Verify notification payloads contain no message body/ciphertext and validate behavior when Firebase is unreachable.

## Offline inbox recovery checks

- Confirm `GET /inbox/sync` returns pages ordered by delivery ID and includes `pending`, `delivered`, and `read` rows only for the authenticated recipient.
- Confirm a client persists a page before sending `delivered` acknowledgements and advances its cursor only after the page is processed.
- Replay the same page and verify the client deduplicates messages by message ID.
- Disconnect WebSocket delivery, send messages, reconnect, and verify the cursor sync recovers them.
- Switch between two accounts on one device and verify the online account check clears the previous account's cached conversations/messages.
- Test offline startup and return-to-online behavior on real Android and Web clients.

## Encrypted local backup and restore

The Storage and data screen supports exporting/importing a `.veyra` backup on Android and Web. The backup encrypts the local cached inbox, conversation cache, language preference, and data-saver preference with AES-256-GCM. A key is derived from a user passphrase using PBKDF2-HMAC-SHA256 (310,000 iterations). The app never includes the login token, FCM token, or private cryptographic keys.

This is a **local-cache backup**, not a complete account archive: inbox cache limits mean it may not contain all historical messages or media. After restore, the inbox cursor resets so the client can resynchronize durable server messages. Restore is restricted to the same Veyra account ID. The user must keep the passphrase safe; Veyra cannot recover it. Since the current messaging E2EE protocol is not yet implemented/audited, do not treat this backup as an audited encrypted-chat archive.

Validate on both targets with `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build web --release`, and `flutter build apk --release`. Exercise create, cancel, restore, wrong passphrase, corrupt file, different account, and cross-device restore scenarios. Backend HTTP-level message-flow coverage is in `backend/app/test_api_e2e.py`; run it with the full backend dependency set installed. This automated API test does not replace real Firebase or Flutter client testing.

## API rate limiting and health probes
- Sensitive HTTP routes have fixed-window limits: Firebase exchange 10/min, message submission 60/min, user search 30/min, push-device registration 20/min; other routes default to 120/min per peer IP and route group.
- Redis is required for shared limits across replicas. The process-local fallback is for local development/tests only. Do not rely on it for production or put the API behind a proxy that fails to normalize/secure client IP headers.
- `GET /health/live` reports process liveness. `GET /health/ready` verifies the database and, when configured, Redis. Configure the platform's readiness/liveness probes to use these endpoints.
- Tune thresholds after observing legitimate traffic; these defaults are conservative starter values, not a substitute for WAF/bot controls, authenticated per-account quotas, or load testing.
