"""Integration tests for durable delivery, idempotency, and acknowledgements."""
import asyncio

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base
from app.models import User, Conversation, Message, MessageDelivery, OutboxEvent
from app.schemas import EncryptedMessageCreate, DeliveryAck
# The full integration tests run in CI after requirements.txt is installed.
pytest.importorskip("pwdlib")
from app import main


@pytest.fixture()
def db_and_users():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    db = Session()
    sender = User(display_name="Sender", phone_number="+15550000001", phone_verified=True)
    recipient = User(display_name="Recipient", phone_number="+15550000002", phone_verified=True)
    db.add_all([sender, recipient])
    db.flush()
    conversation = Conversation(title=None, is_group=False, members=[sender, recipient])
    db.add(conversation)
    db.commit()
    db.refresh(sender)
    db.refresh(recipient)
    db.refresh(conversation)
    try:
        yield db, sender, recipient, conversation
    finally:
        db.close()
        engine.dispose()


def encrypted_payload(key="client-msg-00000001", ciphertext="ciphertext-value-long-enough"):
    return EncryptedMessageCreate(
        ciphertext=ciphertext,
        encryption_version="v1-test",
        sender_device_id="device-test-01",
        idempotency_key=key,
    )


def test_encrypted_send_creates_durable_delivery_and_retry_is_idempotent(db_and_users):
    db, sender, recipient, conversation = db_and_users
    first = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    retry = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))

    assert first["id"] == retry["id"]
    assert db.scalar(select(Message).where(Message.sender_id == sender.id)).id == first["id"]
    deliveries = db.scalars(select(MessageDelivery).where(MessageDelivery.message_id == first["id"])).all()
    assert len(deliveries) == 1
    assert deliveries[0].recipient_id == recipient.id
    assert deliveries[0].status == "pending"


def test_reusing_idempotency_key_for_different_payload_is_rejected(db_and_users):
    db, sender, _, conversation = db_and_users
    asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    with pytest.raises(HTTPException) as exc:
        asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(ciphertext="a-different-ciphertext-value"), db, sender))
    assert exc.value.status_code == 409


def test_delivery_acknowledgement_is_recipient_only_and_monotonic(db_and_users):
    db, sender, recipient, conversation = db_and_users
    message = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    delivery = db.scalar(select(MessageDelivery).where(MessageDelivery.message_id == message["id"]))

    with pytest.raises(HTTPException) as exc:
        main.acknowledge_delivery(delivery.id, DeliveryAck(status="read"), db, sender)
    assert exc.value.status_code == 404

    delivered = main.acknowledge_delivery(delivery.id, DeliveryAck(status="delivered"), db, recipient)
    assert delivered["status"] == "delivered"
    read = main.acknowledge_delivery(delivery.id, DeliveryAck(status="read"), db, recipient)
    assert read["status"] == "read"
    downgraded = main.acknowledge_delivery(delivery.id, DeliveryAck(status="delivered"), db, recipient)
    assert downgraded["status"] == "read"
    assert downgraded["delivered_at"] is not None
    assert downgraded["read_at"] is not None


def test_only_sender_can_query_message_delivery_status(db_and_users):
    db, sender, recipient, conversation = db_and_users
    message = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    status_rows = main.message_delivery_status(conversation.id, message["id"], db, sender)
    assert status_rows == [{"recipient_id": recipient.id, "status": "pending", "delivered_at": None, "read_at": None}]
    with pytest.raises(HTTPException) as exc:
        main.message_delivery_status(conversation.id, message["id"], db, recipient)
    assert exc.value.status_code == 404


def test_message_and_recipient_notification_outbox_are_committed_together(db_and_users):
    db, sender, recipient, conversation = db_and_users
    message = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    events = db.scalars(select(OutboxEvent).where(OutboxEvent.aggregate_id == message["id"])).all()
    realtime = next(event for event in events if event.event_type == "encrypted_message")
    push = next(event for event in events if event.event_type == "push_notification")
    assert len(events) == 2
    assert realtime.recipient_id == recipient.id
    assert realtime.status == "pending"
    assert realtime.payload["type"] == "encrypted_message"
    assert realtime.payload["data"]["ciphertext"] == "ciphertext-value-long-enough"
    assert push.payload == {"type": "new_message", "data": {"conversation_id": conversation.id}}
    assert "ciphertext" not in str(push.payload)


def test_outbox_dispatch_marks_connected_hint_processed(db_and_users, monkeypatch):
    db, sender, recipient, conversation = db_and_users
    message = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    event = db.scalar(select(OutboxEvent).where(OutboxEvent.aggregate_id == message["id"], OutboxEvent.event_type == "encrypted_message"))
    received = []

    async def fake_send_user(user_id, payload):
        received.append((user_id, payload))
        return {"sent": 1, "failed": 0}

    monkeypatch.setattr(main.manager, "send_user", fake_send_user)
    processed = asyncio.run(main.dispatch_outbox_batch(db))
    db.refresh(event)
    assert processed == 2  # realtime event plus no-device push event
    assert event.status == "processed"
    assert event.processed_at is not None
    assert received == [(recipient.id, event.payload)]


def test_outbox_retries_failed_connected_delivery(db_and_users, monkeypatch):
    db, sender, _, conversation = db_and_users
    message = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    event = db.scalar(select(OutboxEvent).where(OutboxEvent.aggregate_id == message["id"], OutboxEvent.event_type == "encrypted_message"))

    async def fake_send_user(user_id, payload):
        return {"sent": 0, "failed": 1}

    monkeypatch.setattr(main.manager, "send_user", fake_send_user)
    processed = asyncio.run(main.dispatch_outbox_batch(db))
    db.refresh(event)
    assert processed == 1  # push event completed independently; realtime event retries
    assert event.status == "pending"
    assert event.attempts == 1
    assert event.last_error == "websocket_send_failed"


def test_outbox_uses_shared_redis_channel_when_configured(db_and_users, monkeypatch):
    db, sender, recipient, conversation = db_and_users
    message = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    event = db.scalar(select(OutboxEvent).where(OutboxEvent.aggregate_id == message["id"], OutboxEvent.event_type == "encrypted_message"))

    class FakeRedis:
        def __init__(self):
            self.published = []
        async def publish(self, channel, payload):
            self.published.append((channel, payload))
            return 1

    fake_redis = FakeRedis()
    monkeypatch.setattr(main.settings, "redis_url", "redis://test/0")
    monkeypatch.setattr(main, "_redis_client", fake_redis)
    processed = asyncio.run(main.dispatch_outbox_batch(db))
    db.refresh(event)

    assert processed == 2  # one Redis hint plus one no-device push event
    assert event.status == "processed"
    assert len(fake_redis.published) == 1
    channel, raw = fake_redis.published[0]
    import json
    envelope = json.loads(raw)
    assert channel == main.REALTIME_CHANNEL
    assert envelope["recipient_id"] == recipient.id
    assert envelope["payload"]["data"]["ciphertext"] == "ciphertext-value-long-enough"


def test_outbox_retries_when_shared_broker_is_unavailable(db_and_users, monkeypatch):
    db, sender, _, conversation = db_and_users
    message = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    event = db.scalar(select(OutboxEvent).where(OutboxEvent.aggregate_id == message["id"], OutboxEvent.event_type == "encrypted_message"))
    monkeypatch.setattr(main.settings, "redis_url", "redis://test/0")
    monkeypatch.setattr(main, "_redis_client", None)

    processed = asyncio.run(main.dispatch_outbox_batch(db))
    db.refresh(event)
    assert processed == 1  # push event completed independently; realtime event retries
    assert event.status == "pending"
    assert event.attempts == 1
    assert event.last_error == "RuntimeError"


def test_push_device_registration_rotates_existing_device_token(db_and_users):
    from app.schemas import PushDeviceRegister
    db, sender, _, _ = db_and_users
    first = main.register_push_device(PushDeviceRegister(device_id="android-1", token="fcm-token-value-long-enough-0001", platform="android"), db, sender)
    second = main.register_push_device(PushDeviceRegister(device_id="android-1", token="fcm-token-value-long-enough-0002", platform="android"), db, sender)
    device = db.scalar(select(main.PushDevice).where(main.PushDevice.user_id == sender.id))
    assert first["status"] == "registered" and second["status"] == "registered"
    assert device.token == "fcm-token-value-long-enough-0002"
    assert device.is_active is True


def test_push_token_cannot_be_claimed_by_another_account(db_and_users):
    from app.schemas import PushDeviceRegister
    db, sender, recipient, _ = db_and_users
    data = PushDeviceRegister(device_id="web-1", token="fcm-token-value-long-enough-0003", platform="web")
    main.register_push_device(data, db, sender)
    with pytest.raises(HTTPException) as exc:
        main.register_push_device(PushDeviceRegister(device_id="web-2", token=data.token, platform="web"), db, recipient)
    assert exc.value.status_code == 409


def test_push_dispatch_sends_generic_notification_without_message_content(db_and_users, monkeypatch):
    db, sender, recipient, conversation = db_and_users
    message = asyncio.run(main.send_encrypted_message(conversation.id, encrypted_payload(), db, sender))
    event = db.scalar(select(OutboxEvent).where(OutboxEvent.aggregate_id == message["id"], OutboxEvent.event_type == "push_notification"))
    device = main.PushDevice(user_id=recipient.id, device_id="android-1", token="fcm-token-value-long-enough-0004", platform="android")
    db.add(device); db.commit()
    captured = {}
    class FakeMessaging:
        class Notification:
            def __init__(self, title, body): self.title, self.body = title, body
        class AndroidConfig:
            def __init__(self, **kwargs): pass
        class WebpushConfig:
            def __init__(self, **kwargs): pass
        class MulticastMessage:
            def __init__(self, **kwargs): captured.update(kwargs)
        def send_each_for_multicast(self, message):
            class Result:
                success = True
                exception = None
            return type("BatchResponse", (), {"responses": [Result()]})()
    monkeypatch.setattr(main, "_firebase_messaging_module", lambda: FakeMessaging())
    assert main.dispatch_push_event(db, event) is True
    assert captured["notification"].title == "New message"
    assert "ciphertext" not in str(captured)
    assert "body" not in captured["data"]


def test_push_token_can_recover_after_local_device_id_reset(db_and_users):
    from app.schemas import PushDeviceRegister
    db, sender, _, _ = db_and_users
    first = PushDeviceRegister(device_id="old-device", token="fcm-token-value-long-enough-0005", platform="web")
    main.register_push_device(first, db, sender)
    second = PushDeviceRegister(device_id="new-device", token=first.token, platform="web")
    result = main.register_push_device(second, db, sender)
    devices = db.scalars(select(main.PushDevice).where(main.PushDevice.user_id == sender.id)).all()
    assert result["device_id"] == "new-device"
    assert len(devices) == 1
    assert devices[0].device_id == "new-device"


def test_push_device_can_be_unregistered(db_and_users):
    from app.schemas import PushDeviceRegister
    db, sender, _, _ = db_and_users
    main.register_push_device(PushDeviceRegister(device_id="android-logout", token="fcm-token-value-long-enough-0006", platform="android"), db, sender)
    result = main.unregister_push_device("android-logout", db, sender)
    assert result["status"] == "unregistered"
    assert db.scalar(select(main.PushDevice).where(main.PushDevice.user_id == sender.id)) is None


def test_cursor_inbox_sync_includes_acknowledged_rows_and_pages(db_and_users):
    db, sender, recipient, conversation = db_and_users
    first = asyncio.run(main.send_encrypted_message(
        conversation.id, encrypted_payload(key="client-msg-sync-0001"), db, sender
    ))
    second = asyncio.run(main.send_encrypted_message(
        conversation.id, encrypted_payload(key="client-msg-sync-0002", ciphertext="second-ciphertext-value-long-enough"), db, sender
    ))
    first_delivery = db.scalar(select(MessageDelivery).where(MessageDelivery.message_id == first["id"]))
    main.acknowledge_delivery(first_delivery.id, DeliveryAck(status="delivered"), db, recipient)

    page_one = main.sync_inbox(after_id=0, limit=1, db=db, user=recipient)
    assert len(page_one["items"]) == 1
    assert page_one["items"][0]["message_id"] == first["id"]
    assert page_one["items"][0]["status"] == "delivered"
    assert page_one["has_more"] is True

    page_two = main.sync_inbox(after_id=page_one["next_after_id"], limit=1, db=db, user=recipient)
    assert len(page_two["items"]) == 1
    assert page_two["items"][0]["message_id"] == second["id"]
    assert page_two["items"][0]["ciphertext"] == "second-ciphertext-value-long-enough"
    assert page_two["has_more"] is False


def test_cursor_inbox_sync_rejects_negative_cursor(db_and_users):
    db, _, recipient, _ = db_and_users
    with pytest.raises(HTTPException) as exc:
        main.sync_inbox(after_id=-1, limit=50, db=db, user=recipient)
    assert exc.value.status_code == 422
