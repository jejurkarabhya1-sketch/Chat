"""HTTP-level end-to-end test for message creation, offline sync and delivery state."""
import pytest
pytest.importorskip("pwdlib")  # Full test runs after backend requirements are installed.

from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from app import main
from app.auth import current_user
from app.db import Base, get_db
from app.models import User


@pytest.fixture
def api_client():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    db = Session()
    sender = User(display_name="E2E Sender", phone_number="+15550000001", phone_verified=True)
    recipient = User(display_name="E2E Recipient", phone_number="+15550000002", phone_verified=True)
    db.add_all([sender, recipient])
    db.commit()
    db.refresh(sender)
    db.refresh(recipient)
    token_users = {"e2e-sender": sender.id, "e2e-recipient": recipient.id}

    def override_db():
        session = Session()
        try:
            yield session
        finally:
            session.close()

    def override_user(request: Request):
        token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
        user_id = token_users.get(token)
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid test token")
        session = Session()
        try:
            return session.get(User, user_id)
        finally:
            session.close()

    main.app.dependency_overrides[get_db] = override_db
    main.app.dependency_overrides[current_user] = override_user
    client = TestClient(main.app)
    try:
        yield client, sender.id, recipient.id
    finally:
        client.close()
        main.app.dependency_overrides.clear()
        db.close()
        engine.dispose()


def test_message_end_to_end_and_access_controls(api_client):
    client, sender_id, recipient_id = api_client

    def call(token, method, path, **kwargs):
        return client.request(method, path, headers={"Authorization": f"Bearer {token}"}, **kwargs)

    response = call("e2e-sender", "POST", "/conversations", json={"member_ids": [recipient_id], "title": "E2E"})
    assert response.status_code == 201, response.text
    conversation_id = response.json()["id"]
    assert set(response.json()["member_ids"]) == {sender_id, recipient_id}

    payload = {
        "ciphertext": "ciphertext-long-enough-for-e2e-test",
        "encryption_version": "v1-test",
        "sender_device_id": "e2e-device",
        "idempotency_key": "e2e-message-key-0001",
    }
    first = call("e2e-sender", "POST", f"/conversations/{conversation_id}/encrypted-messages", json=payload)
    retry = call("e2e-sender", "POST", f"/conversations/{conversation_id}/encrypted-messages", json=payload)
    assert first.status_code == 201, first.text
    assert retry.status_code == 201, retry.text
    assert first.json()["id"] == retry.json()["id"]

    page = call("e2e-recipient", "GET", "/inbox/sync?after_id=0&limit=100")
    assert page.status_code == 200, page.text
    items = page.json()["items"]
    assert len(items) == 1
    assert items[0]["ciphertext"] == payload["ciphertext"]
    delivery_id = items[0]["delivery_id"]
    message_id = first.json()["id"]

    delivered = call("e2e-recipient", "POST", f"/inbox/deliveries/{delivery_id}/ack", json={"status": "delivered"})
    read = call("e2e-recipient", "POST", f"/inbox/deliveries/{delivery_id}/ack", json={"status": "read"})
    downgrade = call("e2e-recipient", "POST", f"/inbox/deliveries/{delivery_id}/ack", json={"status": "delivered"})
    assert delivered.status_code == read.status_code == downgrade.status_code == 200
    assert delivered.json()["status"] == "delivered"
    assert read.json()["status"] == downgrade.json()["status"] == "read"

    sender_status = call("e2e-sender", "GET", f"/conversations/{conversation_id}/messages/{message_id}/delivery-status")
    assert sender_status.status_code == 200
    assert sender_status.json()[0]["status"] == "read"

    forbidden_status = call("e2e-recipient", "GET", f"/conversations/{conversation_id}/messages/{message_id}/delivery-status")
    forbidden_ack = call("e2e-sender", "POST", f"/inbox/deliveries/{delivery_id}/ack", json={"status": "read"})
    assert forbidden_status.status_code == forbidden_ack.status_code == 404
