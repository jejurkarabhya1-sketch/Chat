#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python -m pip install -r "$ROOT/backend/requirements.txt"
python -m compileall -q "$ROOT/backend/app"
(cd "$ROOT/backend" && python -m pytest app/test_smoke.py -q)

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Install Flutter stable to run client checks." >&2
  exit 2
fi
cd "$ROOT/mobile"
if [ ! -d android ] || [ ! -d web ]; then
  flutter create --platforms=android,web --project-name=veyra_messenger .
fi
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --release
