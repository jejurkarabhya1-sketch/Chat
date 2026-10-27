from datetime import datetime
from pydantic import BaseModel, ConfigDict, EmailStr, Field

class UserCreate(BaseModel):
    email: EmailStr
    display_name: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=12, max_length=128)

class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int

class UserOut(BaseModel):
    id: int
    email: EmailStr | None
    display_name: str
    model_config = ConfigDict(from_attributes=True)

class ConversationCreate(BaseModel):
    member_ids: list[int] = Field(min_length=1, max_length=49)
    title: str | None = Field(default=None, max_length=120)

class ConversationOut(BaseModel):
    id: int
    title: str | None
    is_group: bool
    created_at: datetime
    member_ids: list[int]

class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=10000)
    idempotency_key: str | None = Field(default=None, min_length=16, max_length=80, pattern=r"^[A-Za-z0-9._:-]+$")

class MessageOut(BaseModel):
    id: int
    conversation_id: int
    sender_id: int
    body: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

class OtpRequest(BaseModel):
    phone_number: str = Field(pattern=r'^\+[1-9]\d{7,14}$')

class OtpVerify(BaseModel):
    phone_number: str = Field(pattern=r'^\+[1-9]\d{7,14}$')
    code: str = Field(pattern=r'^\d{6}$')
    display_name: str | None = Field(default=None, min_length=1, max_length=80)

class PhoneUserOut(BaseModel):
    id: int
    phone_number: str | None
    display_name: str
    phone_verified: bool
    model_config = ConfigDict(from_attributes=True)

class EncryptedMessageCreate(BaseModel):
    ciphertext: str = Field(min_length=16, max_length=100000)
    encryption_version: str = Field(min_length=1, max_length=40)
    sender_device_id: str = Field(min_length=1, max_length=80)
    idempotency_key: str | None = Field(default=None, min_length=16, max_length=80, pattern=r"^[A-Za-z0-9._:-]+$")

class DeviceKeyUpload(BaseModel):
    device_id: str = Field(min_length=1, max_length=80)
    identity_key_public: str = Field(min_length=16, max_length=4096)
    signed_prekey_public: str = Field(min_length=16, max_length=4096)
    signed_prekey_signature: str = Field(min_length=16, max_length=4096)


class FirebaseExchange(BaseModel):
    id_token: str = Field(min_length=20, max_length=10000)
    display_name: str | None = Field(default=None, min_length=1, max_length=80)


class DeliveryAck(BaseModel):
    status: str = Field(pattern=r"^(delivered|read)$")

class DeliveryOut(BaseModel):
    delivery_id: int
    message_id: int
    conversation_id: int
    sender_id: int
    body: str | None = None
    ciphertext: str | None = None
    encryption_version: str | None = None
    sender_device_id: str | None = None
    created_at: datetime
    status: str


class PushDeviceRegister(BaseModel):
    device_id: str = Field(min_length=1, max_length=80, pattern=r"^[A-Za-z0-9._:-]+$")
    token: str = Field(min_length=20, max_length=4096)
    platform: str = Field(pattern=r"^(android|web)$")
