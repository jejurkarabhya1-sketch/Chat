$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

python -m pip install -r (Join-Path $Root 'backend/requirements.txt')
python -m compileall -q (Join-Path $Root 'backend/app')
Push-Location (Join-Path $Root 'backend')
try { python -m pytest app/test_smoke.py -q } finally { Pop-Location }

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDK not found. Install Flutter stable and Android SDK, then retry.'
}
Push-Location (Join-Path $Root 'mobile')
try {
  if (-not (Test-Path 'android') -or -not (Test-Path 'web')) {
    flutter create --platforms=android,web --project-name=veyra_messenger .
  }
  flutter pub get
  flutter analyze
  flutter test
  flutter build web --release
  flutter build apk --release
} finally { Pop-Location }
