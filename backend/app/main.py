from collections import defaultdict
from contextlib import suppress, asynccontextmanager
from datetime import datetime, timezone, timedelta
import asyncio
import json
import logging
from fastapi import FastAPI, Depends, HTTPException, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from .rate_limit import RateLimitMiddleware
from sqlalchemy.orm import Session, selectinload
from sqlalchemy import select, text
from .config import settings
from .db import Base, engine, get_db, SessionLocal
from .models import User, Conversation, Message, MessageDelivery, DeviceIdentityKey, OutboxEvent, PushDevice
from .schemas import TokenResponse, UserOut, ConversationCreate, ConversationOut, MessageCreate, MessageOut, PhoneUserOut, EncryptedMessageCreate, DeviceKeyUpload, FirebaseExchange, DeliveryAck, DeliveryOut, PushDeviceRegister
from .security import create_access_token, decode_token
from .auth import current_user

if settings.app_env.lower() != "production":
    # Development convenience only. Production schema changes are managed by Alembic.
    # Production startup remains blocked until audited client-side E2EE is available.
    Base.metadata.create_all(bind=engine)

@asynccontextmanager
async def app_lifespan(application: FastAPI):
    global _outbox_task, _broker_task, _redis_client
    if settings.redis_url.strip():
        try:
            from redis.asyncio import Redis
            _redis_client = Redis.from_url(settings.redis_url, decode_responses=True,
                                           socket_connect_timeout=3, socket_timeout=3,
                                           health_check_interval=30)
            await _redis_client.ping()
        except Exception:
            if _redis_client is not None:
                with suppress(Exception):
                    await _redis_client.aclose()
                _redis_client = None
            raise RuntimeError("REDIS_URL is configured but Redis is not reachable")
        _broker_task = asyncio.create_task(_broker_subscriber_loop(), name="veyra-realtime-broker")
    _outbox_task = asyncio.create_task(_outbox_poll_loop(), name="veyra-outbox-dispatcher")
    try:
        yield
    finally:
        for task_name in ("_outbox_task", "_broker_task"):
            task = globals()[task_name]
            if task is not None:
                task.cancel()
                with suppress(asyncio.CancelledError):
                    await task
                globals()[task_name] = None
        if _redis_client is not None:
            with suppress(Exception):
                await _redis_client.aclose()
            _redis_client = None


app = FastAPI(title="Veyra Messaging API", version="0.1.0", lifespan=app_lifespan)
app.add_middleware(RateLimitMiddleware, redis_getter=lambda: _redis_client, enabled=True)
origins = [x.strip() for x in settings.cors_origins.split(",") if x.strip()]
# Flutter web development servers choose a dynamic localhost port. Permit those
# origins only in development; production must use the explicit CORS_ORIGINS list.
local_dev_origin_regex = (
    r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
    if settings.app_env.lower() != "production"
    else None
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=local_dev_origin_regex,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)

class ConnectionManager:
    def __init__(self):
        self.connections: dict[int, set[WebSocket]] = defaultdict(set)

    async def connect(self, user_id: int, ws: WebSocket):
        await ws.accept()
        self.connections[user_id].add(ws)

    def disconnect(self, user_id: int, ws: WebSocket):
        self.connections[user_id].discard(ws)

    async def send_user(self, user_id: int, payload: dict):
        dead = []
        sent = 0
        for ws in list(self.connections.get(user_id, set())):
            try:
                await ws.send_json(payload)
                sent += 1
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(user_id, ws)
        return {"sent": sent, "failed": len(dead)}

manager = ConnectionManager()
_outbox_task: asyncio.Task | None = None
_broker_task: asyncio.Task | None = None
_redis_client = None
REALTIME_CHANNEL = "veyra:realtime:v1"
OUTBOX_BATCH_SIZE = 100
OUTBOX_MAX_ATTEMPTS = 20


def _enqueue_message_notifications(db: Session, message: Message, members: list[User], event_type: str, message_payload: dict) -> None:
    """Write one durable notification event per recipient in the message transaction."""
    for member in members:
        if member.id == message.sender_id:
            continue
        db.add(OutboxEvent(
            event_type=event_type,
            recipient_id=member.id,
            aggregate_id=message.id,
            payload={"type": event_type, "data": message_payload},
            status="pending",
            attempts=0,
            available_at=datetime.now(timezone.utc),
        ))
        # Separate push work so an FCM outage never blocks realtime WebSocket fanout.
        # Push payload deliberately contains no message text or ciphertext.
        db.add(OutboxEvent(
            event_type="push_notification",
            recipient_id=member.id,
            aggregate_id=message.id,
            payload={"type": "new_message", "data": {"conversation_id": message.conversation_id}},
            status="pending",
            attempts=0,
            available_at=datetime.now(timezone.utc),
        ))


def _firebase_messaging_module():
    """Return Firebase Admin messaging module using the configured default app.

    Service credentials should be provided through Application Default Credentials or
    GOOGLE_APPLICATION_CREDENTIALS; never embed service-account JSON in source control.
    """
    if not settings.firebase_project_id.strip():
        return None
    import firebase_admin
    from firebase_admin import messaging
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(options={"projectId": settings.firebase_project_id})
    return messaging


def _is_invalid_fcm_token(exc: Exception) -> bool:
    code = getattr(exc, "code", "") or ""
    return code in {
        "messaging/registration-token-not-registered",
        "messaging/invalid-registration-token",
    }


def dispatch_push_event(db: Session, event: OutboxEvent) -> bool:
    """Send privacy-preserving generic push; returns false when retry should be scheduled."""
    devices = list(db.scalars(select(PushDevice).where(
        PushDevice.user_id == event.recipient_id, PushDevice.is_active.is_(True)
    )).all())
    if not devices:
        return True
    messaging = _firebase_messaging_module()
    if messaging is None:
        # Push is optional until Firebase is configured. Durable inbox remains available.
        return True
    for offset in range(0, len(devices), 500):
        batch = devices[offset:offset + 500]
        try:
            response = messaging.send_each_for_multicast(messaging.MulticastMessage(
                tokens=[device.token for device in batch],
                notification=messaging.Notification(title="New message", body="You have a new message in Veyra."),
                data={
                    "type": "new_message",
                    "conversation_id": str(event.payload.get("data", {}).get("conversation_id", "")),
                    "message_id": str(event.aggregate_id),
                },
                android=messaging.AndroidConfig(priority="high", ttl=timedelta(hours=1)),
                webpush=messaging.WebpushConfig(headers={"TTL": "3600"}),
            ))
        except Exception:
            logging.exception("FCM push batch failed")
            return False
        for device, result in zip(batch, response.responses):
            if result.success:
                device.last_seen_at = datetime.now(timezone.utc)
            elif result.exception and _is_invalid_fcm_token(result.exception):
                device.is_active = False
            elif result.exception:
                logging.warning("FCM push failed for a device (%s)", type(result.exception).__name__)
                # Other tokens in the batch may have succeeded. Retry safely; push is at-least-once.
                return False
    return True


async def dispatch_outbox_batch(db: Session, batch_size: int = OUTBOX_BATCH_SIZE) -> int:
    """Dispatch committed notification hints. Durable inbox rows remain the source of truth.

    With REDIS_URL set, publish to the shared realtime channel so every API instance can fan out
    to its local sockets. Pub/Sub is best-effort; GET /inbox/deliveries is the recovery source.
    Without Redis, use local single-process WebSocket fanout for development only.
    """
    now = datetime.now(timezone.utc)
    stmt = (select(OutboxEvent)
            .where(OutboxEvent.status == "pending", OutboxEvent.available_at <= now)
            .order_by(OutboxEvent.id.asc())
            .limit(max(1, min(batch_size, 500)))
            .with_for_update(skip_locked=True))
    rows = list(db.scalars(stmt).all())
    processed = 0
    for event in rows:
        try:
            if event.event_type == "push_notification":
                if not dispatch_push_event(db, event):
                    raise RuntimeError("fcm_push_dispatch_failed")
                outcome = {"sent": 1, "failed": 0}
            elif settings.redis_url.strip():
                if _redis_client is None:
                    raise RuntimeError("realtime_broker_unavailable")
                envelope = {"recipient_id": event.recipient_id, "payload": event.payload}
                await _redis_client.publish(REALTIME_CHANNEL, json.dumps(envelope, separators=(",", ":")))
                outcome = {"sent": 1, "failed": 0}
            else:
                outcome = await manager.send_user(event.recipient_id, event.payload)
            # No local socket is not an error: inbox recovery is durable and authoritative.
            if outcome.get("failed", 0) > 0 and outcome.get("sent", 0) == 0:
                event.attempts += 1
                event.last_error = "websocket_send_failed"
                if event.attempts >= OUTBOX_MAX_ATTEMPTS:
                    event.status = "dead"
                else:
                    event.available_at = now + timedelta(seconds=min(60, 2 ** min(event.attempts, 6)))
                continue
            event.status = "processed"
            event.processed_at = now
            event.last_error = None
            processed += 1
        except Exception as exc:
            event.attempts += 1
            event.last_error = type(exc).__name__[:120]
            if event.attempts >= OUTBOX_MAX_ATTEMPTS:
                event.status = "dead"
            else:
                event.available_at = now + timedelta(seconds=min(60, 2 ** min(event.attempts, 6)))
    db.commit()
    return processed


async def _outbox_poll_loop() -> None:
    while True:
        try:
            with SessionLocal() as db:
                processed = await dispatch_outbox_batch(db)
            if processed == 0:
                await asyncio.sleep(0.5)
        except asyncio.CancelledError:
            raise
        except Exception:
            logging.exception("Outbox dispatcher iteration failed")
            await asyncio.sleep(1.0)



async def _broker_subscriber_loop() -> None:
    """Subscribe to shared realtime events and fan out only to this instance's sockets.

    Pub/Sub can lose events during disconnects; the durable inbox endpoint is the recovery path.
    Keep payloads limited to notification envelopes and ciphertext for encrypted messages.
    """
    while True:
        pubsub = None
        try:
            if _redis_client is None:
                await asyncio.sleep(1)
                continue
            pubsub = _redis_client.pubsub()
            await pubsub.subscribe(REALTIME_CHANNEL)
            async for item in pubsub.listen():
                if item.get("type") != "message":
                    continue
                try:
                    envelope = json.loads(item.get("data") or "{}")
                    recipient_id = int(envelope["recipient_id"])
                    payload = envelope["payload"]
                    await manager.send_user(recipient_id, payload)
                except (ValueError, TypeError, KeyError, json.JSONDecodeError):
                    logging.warning("Ignoring malformed realtime broker envelope")
                except Exception:
                    logging.exception("Realtime broker fanout failed")
        except asyncio.CancelledError:
            raise
        except Exception:
            logging.exception("Realtime broker subscriber disconnected; reconnecting")
            await asyncio.sleep(1)
        finally:
            if pubsub is not None:
                with suppress(Exception):
                    await pubsub.aclose()


@app.post("/auth/firebase/exchange", response_model=TokenResponse)
def firebase_token_exchange(data: FirebaseExchange, db: Session = Depends(get_db)):
    """Verify Firebase Phone Auth ID token, then issue a short-lived Veyra API token."""
    if not settings.firebase_project_id:
        raise HTTPException(status_code=503, detail="Firebase authentication is not configured on this server")
    try:
        import firebase_admin
        from firebase_admin import auth as firebase_auth
        try:
            firebase_admin.get_app()
        except ValueError:
            firebase_admin.initialize_app(options={"projectId": settings.firebase_project_id})
        claims = firebase_auth.verify_id_token(data.id_token, check_revoked=True)
        phone_number = claims.get("phone_number")
        provider = (claims.get("firebase") or {}).get("sign_in_provider")
        if not phone_number or not claims.get("uid") or provider != "phone":
            raise HTTPException(status_code=401, detail="A verified Firebase phone-auth session is required")
    except HTTPException:
        raise
    except Exception as exc:
        logging.warning("Firebase token verification failed: %s", type(exc).__name__)
        raise HTTPException(status_code=401, detail="Firebase token is invalid, expired, or could not be verified")

    user = db.scalar(select(User).where(User.phone_number == phone_number))
    if not user:
        if not data.display_name or not data.display_name.strip():
            raise HTTPException(status_code=422, detail="display_name is required for a new account")
        user = User(phone_number=phone_number, phone_verified=True, display_name=data.display_name.strip(), email=None, password_hash=None)
        db.add(user)
    else:
        user.phone_verified = True
    db.commit()
    db.refresh(user)
    return TokenResponse(access_token=create_access_token(user.id), expires_in=settings.access_token_minutes * 60)

@app.get("/users/me/phone", response_model=PhoneUserOut)
def phone_me(user: User = Depends(current_user)):
    return user

@app.post("/users/me/push-devices")
def register_push_device(data: PushDeviceRegister, db: Session = Depends(get_db), user: User = Depends(current_user)):
    """Register or rotate an FCM token for this authenticated account/device."""
    now = datetime.now(timezone.utc)
    device = db.scalar(select(PushDevice).where(PushDevice.user_id == user.id, PushDevice.device_id == data.device_id))
    token_owner = db.scalar(select(PushDevice).where(PushDevice.token == data.token))
    if token_owner and token_owner.user_id != user.id:
        # A token should not be silently moved between accounts; require old device logout/revoke.
        raise HTTPException(status_code=409, detail="Push token is already registered to another account")
    if token_owner and (device is None or token_owner.id != device.id):
        # Browser storage reset/reinstall can produce a new device_id for the same token.
        # Remove a stale row occupying that new ID before reassigning the token's row.
        if device is not None:
            db.delete(device)
            db.flush()
        token_owner.device_id = data.device_id
        token_owner.platform = data.platform
        token_owner.is_active = True
        token_owner.last_seen_at = now
        token_owner.updated_at = now
    elif device:
        device.token = data.token
        device.platform = data.platform
        device.is_active = True
        device.last_seen_at = now
        device.updated_at = now
    else:
        db.add(PushDevice(user_id=user.id, device_id=data.device_id, token=data.token, platform=data.platform,
                          is_active=True, created_at=now, updated_at=now, last_seen_at=now))
    db.commit()
    return {"status": "registered", "device_id": data.device_id, "platform": data.platform}


@app.delete("/users/me/push-devices/{device_id}")
def unregister_push_device(device_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    device = db.scalar(select(PushDevice).where(PushDevice.user_id == user.id, PushDevice.device_id == device_id))
    if device is None:
        raise HTTPException(status_code=404, detail="Push device not found")
    db.delete(device)
    db.commit()
    return {"status": "unregistered", "device_id": device_id}


@app.post("/users/me/device-keys")
def upload_device_keys(data: DeviceKeyUpload, db: Session = Depends(get_db), user: User = Depends(current_user)):
    existing = db.scalar(select(DeviceIdentityKey).where(DeviceIdentityKey.user_id == user.id, DeviceIdentityKey.device_id == data.device_id))
    if existing:
        existing.identity_key_public = data.identity_key_public
        existing.signed_prekey_public = data.signed_prekey_public
        existing.signed_prekey_signature = data.signed_prekey_signature
    else:
        db.add(DeviceIdentityKey(user_id=user.id, device_id=data.device_id, identity_key_public=data.identity_key_public, signed_prekey_public=data.signed_prekey_public, signed_prekey_signature=data.signed_prekey_signature))
    db.commit()
    return {"status": "stored_public_keys_only", "device_id": data.device_id}

@app.get("/users/{target_user_id}/device-keys")
def get_device_keys(target_user_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if target_user_id == user.id:
        raise HTTPException(status_code=400, detail="Use your local key store for your own private keys")
    keys = db.scalars(select(DeviceIdentityKey).where(DeviceIdentityKey.user_id == target_user_id)).all()
    return [{"device_id": k.device_id, "identity_key_public": k.identity_key_public, "signed_prekey_public": k.signed_prekey_public, "signed_prekey_signature": k.signed_prekey_signature} for k in keys]

def _delivery_rows(db: Session, message: Message, members: list[User]) -> None:
    """Create durable offline-delivery records in the same transaction as the message."""
    for member in members:
        if member.id != message.sender_id:
            db.add(MessageDelivery(message_id=message.id, recipient_id=member.id, status="pending"))


def _encrypted_payload(message: Message) -> dict:
    return {
        "id": message.id,
        "conversation_id": message.conversation_id,
        "sender_id": message.sender_id,
        "ciphertext": message.ciphertext,
        "encryption_version": message.encryption_version,
        "sender_device_id": message.sender_device_id,
        "created_at": message.created_at.isoformat(),
    }


@app.post("/conversations/{conversation_id}/encrypted-messages", status_code=201)
async def send_encrypted_message(conversation_id: int, data: EncryptedMessageCreate, db: Session = Depends(get_db), user: User = Depends(current_user)):
    conv = db.scalar(select(Conversation).where(Conversation.id == conversation_id).options(selectinload(Conversation.members)))
    if not conv or user.id not in {member.id for member in conv.members}:
        raise HTTPException(status_code=404, detail="Conversation not found")

    # Idempotency makes retries safe after timeouts or reconnects.
    if data.idempotency_key:
        existing = db.scalar(select(Message).where(Message.sender_id == user.id, Message.idempotency_key == data.idempotency_key))
        if existing:
            if existing.conversation_id != conversation_id or existing.ciphertext != data.ciphertext:
                raise HTTPException(status_code=409, detail="Idempotency key was already used for a different message")
            return _encrypted_payload(existing)

    msg = Message(
        conversation_id=conversation_id,
        sender_id=user.id,
        body="[encrypted]",
        ciphertext=data.ciphertext,
        encryption_version=data.encryption_version,
        sender_device_id=data.sender_device_id,
        idempotency_key=data.idempotency_key,
    )
    db.add(msg)
    db.flush()
    _delivery_rows(db, msg, conv.members)
    encrypted_payload = _encrypted_payload(msg)
    _enqueue_message_notifications(db, msg, conv.members, "encrypted_message", encrypted_payload)
    db.commit()
    db.refresh(msg)
    return encrypted_payload


@app.get("/inbox/deliveries", response_model=list[DeliveryOut])
def pending_deliveries(limit: int = 50, db: Session = Depends(get_db), user: User = Depends(current_user)):
    """Fetch pending durable deliveries for offline/reconnecting clients."""
    limit = max(1, min(limit, 100))
    rows = db.scalars(
        select(MessageDelivery)
        .where(MessageDelivery.recipient_id == user.id, MessageDelivery.status == "pending")
        .options(selectinload(MessageDelivery.message))
        .order_by(MessageDelivery.id.asc())
        .limit(limit)
    ).all()
    result = []
    for delivery in rows:
        message = delivery.message
        result.append(DeliveryOut(
            delivery_id=delivery.id,
            message_id=message.id,
            conversation_id=message.conversation_id,
            sender_id=message.sender_id,
            body=message.body if message.ciphertext is None else None,
            ciphertext=message.ciphertext,
            encryption_version=message.encryption_version,
            sender_device_id=message.sender_device_id,
            created_at=message.created_at,
            status=delivery.status,
        ))
    return result


@app.get("/inbox/sync")
def sync_inbox(after_id: int = 0, limit: int = 100, db: Session = Depends(get_db), user: User = Depends(current_user)):
    """Cursor-based inbox recovery including already-acknowledged rows.

    The client persists a page locally before advancing its cursor. Re-reading a page is safe;
    clients deduplicate by message_id. Including delivered/read rows lets a reinstalled client
    recover messages even if a previous installation had acknowledged them.
    """
    if after_id < 0:
        raise HTTPException(status_code=422, detail="after_id must be zero or greater")
    limit = max(1, min(limit, 100))
    rows = db.scalars(
        select(MessageDelivery)
        .where(MessageDelivery.recipient_id == user.id, MessageDelivery.id > after_id)
        .options(selectinload(MessageDelivery.message))
        .order_by(MessageDelivery.id.asc())
        .limit(limit + 1)
    ).all()
    has_more = len(rows) > limit
    page = rows[:limit]
    items = []
    for delivery in page:
        message = delivery.message
        items.append(DeliveryOut(
            delivery_id=delivery.id,
            message_id=message.id,
            conversation_id=message.conversation_id,
            sender_id=message.sender_id,
            body=message.body if message.ciphertext is None else None,
            ciphertext=message.ciphertext,
            encryption_version=message.encryption_version,
            sender_device_id=message.sender_device_id,
            created_at=message.created_at,
            status=delivery.status,
        ).model_dump(mode="json"))
    return {
        "items": items,
        "next_after_id": page[-1].id if page else after_id,
        "has_more": has_more,
    }


@app.post("/inbox/deliveries/{delivery_id}/ack")
def acknowledge_delivery(delivery_id: int, data: DeliveryAck, db: Session = Depends(get_db), user: User = Depends(current_user)):
    delivery = db.get(MessageDelivery, delivery_id)
    if not delivery or delivery.recipient_id != user.id:
        raise HTTPException(status_code=404, detail="Delivery not found")
    now = datetime.now(timezone.utc)
    # Status is monotonic: read cannot be downgraded to delivered.
    if data.status == "read":
        delivery.status = "read"
        delivery.read_at = delivery.read_at or now
        delivery.delivered_at = delivery.delivered_at or now
    elif delivery.status == "pending":
        delivery.status = "delivered"
        delivery.delivered_at = now
    db.commit()
    return {
        "delivery_id": delivery.id,
        "message_id": delivery.message_id,
        "status": delivery.status,
        "delivered_at": delivery.delivered_at.isoformat() if delivery.delivered_at else None,
        "read_at": delivery.read_at.isoformat() if delivery.read_at else None,
    }


@app.get("/conversations/{conversation_id}/messages/{message_id}/delivery-status")
def message_delivery_status(conversation_id: int, message_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    message = db.get(Message, message_id)
    if not message or message.conversation_id != conversation_id or message.sender_id != user.id:
        raise HTTPException(status_code=404, detail="Message not found")
    rows = db.scalars(select(MessageDelivery).where(MessageDelivery.message_id == message_id).order_by(MessageDelivery.recipient_id.asc())).all()
    return [{
        "recipient_id": row.recipient_id,
        "status": row.status,
        "delivered_at": row.delivered_at.isoformat() if row.delivered_at else None,
        "read_at": row.read_at.isoformat() if row.read_at else None,
    } for row in rows]

@app.get("/health")
def health():
    # Backwards-compatible liveness endpoint; no internal dependency details.
    return {"status": "ok"}


@app.get("/health/live")
def health_live():
    return {"status": "alive"}


@app.get("/health/ready")
async def health_ready(db: Session = Depends(get_db)):
    """Readiness probe: report ready only when required dependencies respond."""
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        raise HTTPException(status_code=503, detail="Database unavailable")
    if settings.redis_url.strip():
        if _redis_client is None:
            raise HTTPException(status_code=503, detail="Realtime service unavailable")
        try:
            await _redis_client.ping()
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=503, detail="Realtime service unavailable")
    return {"status": "ready"}

@app.get("/users/me", response_model=UserOut)
def me(user: User = Depends(current_user)):
    return user

@app.get("/users/search", response_model=list[UserOut])
def search_users(q: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    q = q.strip()
    if len(q) < 2:
        return []
    return list(db.scalars(select(User).where(User.id != user.id, User.display_name.ilike(f"%{q}%")).limit(20)).all())

def conversation_out(c: Conversation):
    return ConversationOut(id=c.id, title=c.title, is_group=c.is_group, created_at=c.created_at, member_ids=[m.id for m in c.members])

@app.post("/conversations", response_model=ConversationOut, status_code=201)
def create_conversation(data: ConversationCreate, db: Session = Depends(get_db), user: User = Depends(current_user)):
    ids = list(dict.fromkeys([user.id] + data.member_ids))
    if len(ids) > 50:
        raise HTTPException(status_code=422, detail="Maximum 50 members")
    members = list(db.scalars(select(User).where(User.id.in_(ids))).all())
    if len(members) != len(ids):
        raise HTTPException(status_code=404, detail="One or more users not found")
    conv = Conversation(title=data.title, is_group=len(ids) > 2, members=members)
    db.add(conv)
    db.commit()
    db.refresh(conv)
    return conversation_out(conv)

@app.get("/conversations", response_model=list[ConversationOut])
def list_conversations(db: Session = Depends(get_db), user: User = Depends(current_user)):
    items = db.scalars(select(Conversation).join(Conversation.members).where(User.id == user.id).options(selectinload(Conversation.members)).order_by(Conversation.created_at.desc())).unique().all()
    return [conversation_out(c) for c in items]

@app.get("/conversations/{conversation_id}/messages", response_model=list[MessageOut])
def history(conversation_id: int, limit: int = 50, before_id: int | None = None, db: Session = Depends(get_db), user: User = Depends(current_user)):
    conv = db.get(Conversation, conversation_id)
    if not conv or user not in conv.members:
        raise HTTPException(status_code=404, detail="Conversation not found")
    limit = max(1, min(limit, 100))
    stmt = select(Message).where(Message.conversation_id == conversation_id)
    if before_id:
        stmt = stmt.where(Message.id < before_id)
    return list(db.scalars(stmt.order_by(Message.id.desc()).limit(limit)).all())[::-1]

@app.post("/conversations/{conversation_id}/messages", response_model=MessageOut, status_code=201)
async def send_message(conversation_id: int, data: MessageCreate, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if not settings.allow_plaintext_messages:
        raise HTTPException(status_code=410, detail="Plaintext messaging is disabled. Use the encrypted-message protocol.")
    conv = db.get(Conversation, conversation_id)
    if not conv or user not in conv.members:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if data.idempotency_key:
        existing = db.scalar(select(Message).where(Message.sender_id == user.id, Message.idempotency_key == data.idempotency_key))
        if existing:
            if existing.conversation_id != conversation_id or existing.body != data.body.strip():
                raise HTTPException(status_code=409, detail="Idempotency key was already used for a different message")
            return existing
    msg = Message(conversation_id=conversation_id, sender_id=user.id, body=data.body.strip(), idempotency_key=data.idempotency_key)
    if not msg.body:
        raise HTTPException(status_code=422, detail="Message cannot be blank")
    db.add(msg)
    db.flush()
    _delivery_rows(db, msg, conv.members)
    message_payload = MessageOut.model_validate(msg).model_dump(mode="json")
    _enqueue_message_notifications(db, msg, conv.members, "message", message_payload)
    db.commit()
    db.refresh(msg)
    return msg

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket, token: str):
    try:
        user_id = decode_token(token)
    except HTTPException:
        await ws.close(code=4401)
        return
    with SessionLocal() as db:
        if not db.get(User, user_id):
            await ws.close(code=4401)
            return
    await manager.connect(user_id, ws)
    try:
        while True:
            # Client can send ping frames as JSON; messages are sent through authenticated REST endpoint.
            await ws.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(user_id, ws)
