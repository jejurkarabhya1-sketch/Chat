"""Add idempotent message submission and durable recipient delivery state.

Revision ID: 0002_delivery
Revises: 0001_initial
Create Date: 2026-10-26
"""
from alembic import op
import sqlalchemy as sa

revision = "0002_delivery"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Batch mode works on SQLite CI/dev databases and PostgreSQL production databases.
    with op.batch_alter_table("messages") as batch_op:
        batch_op.add_column(sa.Column("idempotency_key", sa.String(length=80), nullable=True))
        batch_op.create_unique_constraint("uq_messages_sender_idempotency", ["sender_id", "idempotency_key"])
    op.create_table(
        "message_deliveries",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("message_id", sa.Integer(), sa.ForeignKey("messages.id", ondelete="CASCADE"), nullable=False),
        sa.Column("recipient_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("delivered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("message_id", "recipient_id", name="uq_delivery_message_recipient"),
    )
    op.create_index("ix_message_deliveries_message_id", "message_deliveries", ["message_id"])
    op.create_index("ix_message_deliveries_recipient_id", "message_deliveries", ["recipient_id"])
    op.create_index("ix_message_deliveries_status", "message_deliveries", ["status"])
    op.create_index("ix_delivery_recipient_status_id", "message_deliveries", ["recipient_id", "status", "id"])


def downgrade() -> None:
    op.drop_index("ix_delivery_recipient_status_id", table_name="message_deliveries")
    op.drop_index("ix_message_deliveries_status", table_name="message_deliveries")
    op.drop_index("ix_message_deliveries_recipient_id", table_name="message_deliveries")
    op.drop_index("ix_message_deliveries_message_id", table_name="message_deliveries")
    op.drop_table("message_deliveries")
    with op.batch_alter_table("messages") as batch_op:
        batch_op.drop_constraint("uq_messages_sender_idempotency", type_="unique")
        batch_op.drop_column("idempotency_key")
