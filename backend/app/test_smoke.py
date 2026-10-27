"""Source-level guardrails. Full integration tests require installed dependencies and Firebase credentials."""
from pathlib import Path
import pytest

from app.config import Settings

ROOT = Path(__file__).resolve().parents[1]

def test_firebase_phone_auth_exchange_exists():
    source = (ROOT / "app" / "main.py").read_text()
    assert '/auth/firebase/exchange' in source
    assert 'verify_id_token(data.id_token, check_revoked=True)' in source
    assert 'phone_number = claims.get("phone_number")' in source
    assert 'provider != "phone"' in source
    assert 'OTP_DEV_MODE' not in source
    assert 'twilio' not in source.lower()

def test_encrypted_message_route_exists():
    source = (ROOT / "app" / "main.py").read_text()
    assert '/encrypted-messages' in source
    assert 'ciphertext=data.ciphertext' in source

def test_no_private_key_columns_on_server_models():
    source = (ROOT / "app" / "models.py").read_text().lower()
    assert 'identity_key_public' in source
    assert 'private_key:' not in source


def test_production_config_fails_closed_on_weak_secret():
    source = (ROOT / "app" / "config.py").read_text()
    assert 'Production requires a unique JWT_SECRET' in source
    assert 'Production must use PostgreSQL' in source
    assert 'Production must disable plaintext messages' in source

def test_plaintext_messages_can_be_disabled():
    source = (ROOT / "app" / "main.py").read_text()
    assert 'if not settings.allow_plaintext_messages:' in source
    assert 'Plaintext messaging is disabled' in source


def test_flutter_web_phone_auth_uses_web_confirmation_flow():
    source = (ROOT.parent / "mobile" / "lib" / "main.dart").read_text()
    assert "show kIsWeb" in source
    assert "signInWithPhoneNumber(number)" in source
    assert "webConfirmationResult!.confirm(code.text.trim())" in source


def test_client_build_workflow_checks_both_targets():
    workflow = (ROOT.parent / ".github" / "workflows" / "build-clients.yml").read_text()
    assert "flutter analyze" in workflow
    assert "flutter test" in workflow
    assert "flutter build web --release" in workflow
    assert "flutter build apk --release" in workflow
    assert "Configure Android compile SDK" in workflow
    assert "androidExtension.compileSdk = 36" in workflow
    assert "afterEvaluate" not in workflow
    assert "androidComponents.finalizeDsl" in workflow
    assert 'sdkmanager" "platforms;android-36"' in workflow
    assert "actions/upload-artifact@v4" in workflow


def test_production_is_blocked_until_audited_e2ee_exists():
    source = (ROOT / "app" / "config.py").read_text()
    assert "Production startup is blocked: the client-side end-to-end encryption protocol is not implemented and independently audited" in source
    assert "allow_plaintext_messages: bool = False" in source

def test_compose_disables_plaintext_by_default():
    source = (ROOT.parent / "docker-compose.yml").read_text()
    assert "ALLOW_PLAINTEXT_MESSAGES:-false" in source


def test_valid_looking_production_config_still_fails_closed():
    with pytest.raises(ValueError, match="Production startup is blocked"):
        Settings(
            app_env="production",
            database_url="postgresql+psycopg://user:password@localhost/app",
            jwt_secret="a" * 48,
            firebase_project_id="test-project",
            allow_plaintext_messages=False,
        )


def test_client_disables_plaintext_messaging_by_default():
    config = (ROOT.parent / "mobile" / "lib" / "config.dart").read_text()
    main = (ROOT.parent / "mobile" / "lib" / "main.dart").read_text()
    assert "defaultValue: false" in config
    assert "Sending is disabled until end-to-end encryption is implemented and reviewed." in main


def test_durable_delivery_and_ack_routes_exist():
    source = (ROOT / "app" / "main.py").read_text()
    assert '"/inbox/deliveries"' in source
    assert '"/inbox/deliveries/{delivery_id}/ack"' in source
    assert '"/conversations/{conversation_id}/messages/{message_id}/delivery-status"' in source
    assert "_delivery_rows(db, msg, conv.members)" in source
    assert "Idempotency key was already used for a different message" in source

def test_delivery_model_has_unique_recipient_and_monotonic_status_fields():
    source = (ROOT / "app" / "models.py").read_text()
    assert 'UniqueConstraint("message_id", "recipient_id", name="uq_delivery_message_recipient")' in source
    assert 'delivered_at:' in source and 'read_at:' in source
    assert 'UniqueConstraint("sender_id", "idempotency_key", name="uq_messages_sender_idempotency")' in source

def test_delivery_migration_is_chained_after_initial_schema():
    source = (ROOT / "migrations" / "versions" / "0002_durable_delivery.py").read_text()
    assert 'revision = "0002_delivery"' in source
    assert 'down_revision = "0001_initial"' in source
    assert 'message_deliveries' in source


def test_push_registration_routes_and_generic_payload_are_present():
    source = (ROOT / "app" / "main.py").read_text()
    assert '"/users/me/push-devices"' in source
    assert '"/users/me/push-devices/{device_id}"' in source
    assert 'body="You have a new message in Veyra."' in source
    assert 'payload={"type": "new_message", "data": {"conversation_id": message.conversation_id}}' in source

def test_push_device_migration_follows_outbox():
    source = (ROOT / "migrations" / "versions" / "0004_push_devices.py").read_text()
    assert 'revision = "0004_push"' in source
    assert 'down_revision = "0003_outbox"' in source
    assert 'push_devices' in source
