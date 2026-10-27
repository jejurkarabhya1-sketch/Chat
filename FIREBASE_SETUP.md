# Firebase Phone Authentication Setup

Veyra uses Firebase Phone Authentication for OTP delivery and verification. Firebase phone SMS is not universally free: billing, quotas, country-specific rates, and abuse protections depend on your Firebase plan and current pricing. Firebase test phone numbers can be used during development without sending real SMS.

## 1. Create and configure Firebase

1. Create a project at https://console.firebase.google.com/.
2. Add an Android app using the exact application ID of the Flutter Android project.
3. Enable **Authentication → Sign-in method → Phone**.
4. Generate the Android platform folder if missing: from `mobile/`, run `flutter create --platforms=android .`.
5. Choose one client configuration path:
   - Standard Android setup: download `google-services.json` into `mobile/android/app/` and configure the Google Services Gradle plugin following https://firebase.google.com/docs/flutter/setup.
   - CI/build-define setup: set `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, and `FIREBASE_PROJECT_ID` as GitHub Actions repository variables. These are Firebase client configuration values, not server credentials.
6. Add the Android SHA-1 and SHA-256 fingerprints in Firebase project settings.
7. For development, add Firebase test phone numbers in Authentication settings to avoid sending SMS.

## 2. Configure Firebase for Web

1. In Firebase project settings, add a **Web app** and copy its `apiKey`, `appId`, `messagingSenderId`, `projectId`, and `authDomain` values.
2. For local Web builds, pass them using `--dart-define` flags. Example (replace every placeholder):

```bash
cd mobile
flutter build web --release \
  --dart-define=API_BASE_URL=https://your-api.example.com \
  --dart-define=FIREBASE_WEB_API_KEY=your-web-api-key \
  --dart-define=FIREBASE_WEB_APP_ID=your-web-app-id \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=your-sender-id \
  --dart-define=FIREBASE_PROJECT_ID=your-project-id \
  --dart-define=FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
```

3. Add the deployed web domain to Firebase Authentication's authorized domains. For GitHub Pages, use the repository's Pages hostname.
4. For the automated Pages workflow, add the same values as repository **Actions variables**, along with `API_BASE_URL`, then run `.github/workflows/deploy-web-pages.yml` manually.
5. Set backend `CORS_ORIGINS` to the exact browser origin(s) that will host the app. Do not use a wildcard for production.

If web Firebase values are missing, the web bundle still compiles and opens a setup screen instead of crashing at startup. That is a configuration state, not a functioning sign-in flow.

## 3. Configure the backend

Set `FIREBASE_PROJECT_ID` in the backend environment. For local development, create a Firebase service account in Firebase/Google Cloud project settings, save it outside the repository, and set `GOOGLE_APPLICATION_CREDENTIALS` to its path before running the API. Never commit the JSON key or put it in the Flutter app. In production, prefer a managed runtime identity / Application Default Credentials instead of a downloaded service-account key.

Install backend dependencies and run the API:

```bash
cd backend
python -m venv .venv
# activate the environment, then:
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Configure `mobile/lib/config.dart` for the target environment. Android emulator uses `http://10.0.2.2:8000`; physical devices need a reachable HTTPS backend in production.

## 4. Important security notes

- The app signs in with Firebase, obtains a Firebase ID token, then sends it to `/auth/firebase/exchange`. The backend verifies the token with Firebase Admin and issues a separate short-lived Veyra API token.
- Firebase authentication does **not** provide end-to-end message encryption. The current encrypted-message endpoint and public-key records are scaffolding only; a vetted protocol, client-side implementation, key verification, multi-device design, and independent audit are still required.
- Configure production quotas, monitoring, App Check where appropriate, abuse prevention, HTTPS/WSS, database migrations, backups, and rate limiting before public release.
- SMS pricing and availability vary by country and may change. Check current Firebase pricing before launch.

## Push notifications (optional, Android and Web)

Push registration is best-effort and does not block sign-in if permission is denied or setup is incomplete. The server sends a generic notification (`New message` / `You have a new message in Veyra.`); it deliberately does not include message text or ciphertext. The durable inbox remains the source of truth when push is unavailable.

1. Enable Firebase Cloud Messaging for the same Firebase project used for Phone Auth.
2. For Android, ensure the Android app is registered in Firebase and the generated Android project uses the matching `google-services.json` / Firebase configuration. On Android 13+, allow notification permission when prompted.
3. For Web, configure HTTPS hosting, create/use a Web Push certificate (VAPID key), and add the GitHub Actions repository variable `FIREBASE_WEB_VAPID_KEY`.
4. Set the Web Firebase values as GitHub Actions repository variables. The Web build workflow substitutes them into `mobile/web/firebase-messaging-sw.js` when all values are present. For local Web builds, replace the public placeholders in that file yourself. This file must be served from the site root. Never put Firebase Admin service-account credentials in the web app or this worker.
5. Configure the backend with `FIREBASE_PROJECT_ID` and Application Default Credentials or `GOOGLE_APPLICATION_CREDENTIALS` pointing to a Firebase Admin service account file mounted read-only. Never commit that file.
6. Run Alembic migrations through `alembic upgrade head`; migration `0004_push` creates the push-device registry.
7. Sign in on each target, grant notification permission, and verify `POST /users/me/push-devices` succeeds. Verify logout unregisters that device. Test foreground/background behavior on real devices and deployed HTTPS hosting.

The worker currently opens/focuses the Veyra web app on notification click; deep-link navigation to a specific conversation is a later client-routing task. Browser push support and permission behavior vary by browser.
