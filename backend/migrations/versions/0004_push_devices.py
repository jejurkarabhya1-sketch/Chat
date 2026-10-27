"""Add registered push devices for privacy-preserving FCM notifications.

Revision ID: 0004_push
Revises: 0003_outbox
Create Date: 2026-10-26
"""
from alembic import op
import sqlalchemy as sa

revision = "0004_push"
down_revision = "0003_outbox"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "push_devices",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("device_id", sa.String(length=80), nullable=False),
        sa.Column("token", sa.Text(), nullable=False),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "device_id", name="uq_push_device_user_device"),
        sa.UniqueConstraint("token", name="uq_push_device_token"),
    )
    op.create_index("ix_push_devices_user_id", "push_devices", ["user_id"])
    op.create_index("ix_push_devices_is_active", "push_devices", ["is_active"])
    op.create_index("ix_push_devices_user_active", "push_devices", ["user_id", "is_active"])


def downgrade() -> None:
    op.drop_index("ix_push_devices_user_active", table_name="push_devices")
    op.drop_index("ix_push_devices_is_active", table_name="push_devices")
    op.drop_index("ix_push_devices_user_id", table_name="push_devices")
    op.drop_table("push_devices")
