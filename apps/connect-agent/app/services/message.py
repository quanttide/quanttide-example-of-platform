"""
消息服务：发送和编辑消息。
"""

from __future__ import annotations

from datetime import datetime, timezone

from app.events import EventBus, MessageEdited, MessageSent
from app.models import Message, Role
from app.storage import Storage


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class MessageService:
    def __init__(self, storage: Storage, event_bus: EventBus | None = None) -> None:
        self.storage = storage
        self.event_bus = event_bus or EventBus()

    def send(self, content: str, role: Role) -> Message:
        msg = Message(content=content, role=role)
        self.storage.add_message(msg)
        self.event_bus.publish(
            MessageSent(
                message_id=msg.id,
                content=msg.content,
                role=msg.role.value,
                timestamp=msg.created_at,
            )
        )
        return msg

    def edit(self, message_id: str, new_content: str) -> Message | None:
        msg = self.storage.update_message(message_id, new_content)
        if msg:
            self.event_bus.publish(
                MessageEdited(
                    message_id=msg.id,
                    new_content=msg.content,
                    updated_at=msg.updated_at or _utcnow(),
                )
            )
        return msg
