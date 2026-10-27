from datetime import datetime, timezone
from sqlalchemy import String, Text, DateTime, ForeignKey, Table, Column, UniqueConstraint, Index, JSON, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .db import Base

conversation_members = Table(
    "conversation_members", Base.metadata,
    Column("conversation_id", ForeignKey("conversations.id", ondelete="CASCADE"), primary_key=True),
    Column("user_id", ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
)

def utcnow():
    return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str | None] = mapped_column(String(254), unique=True, index=True, nullable=True)
    display_name: Mapped[str] = mapped_column(String(80))
    phone_number: Mapped[str | None] = mapped_column(String(16), unique=True, index=True, nullable=True)
    phone_verified: Mapped[bool] = mapped_column(default=False)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    conversations: Mapped[list["Conversation"]] = relationship(secondary=conversation_members, back_populates="members")

class Conversation(Base):
    __tablename__ = "conversations"
    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    is_group: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    members: Mapped[list[User]] = relationship(secondary=conversation_members, back_populates="conversations")
    messages: Mapped[list["Message"]] = relationship(back_populates="conversation", cascade="all, delete-orphan")

class Message(Base):
    __tablename__ = "messages"
    __table_args__ = (UniqueConstraint("sender_id", "idempotency_key", name="uq_messages_sender_idempotency"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    conversation_id: Mapped[int] = mapped_column(ForeignKey("conversations.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    body: Mapped[str] = mapped_column(Text)
    ciphertext: Mapped[str | None] = mapped_column(Text, nullable=True)
    encryption_version: Mapped[str | None] = mapped_column(String(40), nullable=True)
    sender_device_id: Mapped[str | None] = mapped_column(String(80), nullable=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(80), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    conversation: Mapped[Conversation] = relationship(back_populates="messages")

class OtpChallenge(Base):
    __tablename__ = "otp_challenges"
    id: Mapped[int] = mapped_column(primary_key=True)
    phone_number: Mapped[str] = mapped_column(String(16), index=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(default=0)
    consumed: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

class DeviceIdentityKey(Base):
    """Public key material only. Private keys must never be uploaded to the server."""
    __tablename__ = "device_identity_keys"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    device_id: Mapped[str] = mapped_column(String(80))
    identity_key_public: Mapped[str] = mapped_column(Text)
    signed_prekey_public: Mapped[str] = mapped_column(Text)
    signed_prekey_signature: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class MessageDelivery(Base):
    """Durable per-recipient delivery state. The message row and these rows are committed atomically."""
    __tablename__ = "message_deliveries"
    __table_args__ = (
        UniqueConstraint("message_id", "recipient_id", name="uq_delivery_message_recipient"),
        Index("ix_delivery_recipient_status_id", "recipient_id", "status", "id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    message_id: Mapped[int] = mapped_column(ForeignKey("messages.id", ondelete="CASCADE"), index=True)
    recipient_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    message: Mapped[Message] = relationship()


class OutboxEvent(Base):
    """Transactional notification outbox. Payloads contain only delivery envelopes, never plaintext for encrypted messages."""
    __tablename__ = "outbox_events"
    __table_args__ = (Index("ix_outbox_status_available_id", "status", "available_at", "id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    event_type: Mapped[str] = mapped_column(String(48))
    recipient_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    aggregate_id: Mapped[int] = mapped_column(Integer, index=True)  # message ID
    payload: Mapped[dict] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    attempts: Mapped[int] = mapped_column(default=0)
    available_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_error: Mapped[str | None] = mapped_column(String(120), nullable=True)


class PushDevice(Base):
    """Registered FCM token for one authenticated user/device. Tokens are credentials and must not be logged."""
    __tablename__ = "push_devices"
    __table_args__ = (
        UniqueConstraint("user_id", "device_id", name="uq_push_device_user_device"),
        UniqueConstraint("token", name="uq_push_device_token"),
        Index("ix_push_devices_user_active", "user_id", "is_active"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    device_id: Mapped[str] = mapped_column(String(80))
    token: Mapped[str] = mapped_column(Text)
    platform: Mapped[str] = mapped_column(String(16))
    is_active: Mapped[bool] = mapped_column(default=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
