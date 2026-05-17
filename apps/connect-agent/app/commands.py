"""
命令处理层：实现 DRD-events 定义的 7 个命令。
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timezone

from app.events import (
    ConsensusConfirmed,
    ConsensusDeprecated,
    ConsensusProposed,
    DomainEvent,
    EventHandler,
    MessageEdited,
    MessageLinkedToConsensus,
    MessageSent,
    MessageUnlinkedFromConsensus,
)
from app.models import Consensus, ConsensusStatus, Message, Relation, Role
from app.storage import Storage


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class EventBus:
    """简单的事件总线，注册 handler 并发布事件。"""

    def __init__(self) -> None:
        self._handlers: list[EventHandler] = []

    def register(self, handler: EventHandler | Callable[[DomainEvent], None]) -> None:
        self._handlers.append(handler)

    def publish(self, event: DomainEvent) -> None:
        for h in self._handlers:
            if hasattr(h, "handle"):
                h.handle(event)
            else:
                h(event)


class Conversation:
    """对话会话，封装 7 个命令。"""

    def __init__(self, storage: Storage, event_bus: EventBus | None = None) -> None:
        self.storage = storage
        self.event_bus = event_bus or EventBus()

    # ---- Message 命令 ----

    def send_message(self, content: str, role: Role) -> Message:
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

    def edit_message(self, message_id: str, new_content: str) -> Message | None:
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

    # ---- Consensus 命令 ----

    def propose_consensus(
        self, content: str, related_message_ids: list[str]
    ) -> Consensus:
        c = Consensus(content=content, status=ConsensusStatus.proposed)
        self.storage.add_consensus(c)
        for mid in related_message_ids:
            if self.storage.get_message(mid):
                r = Relation(message_id=mid, consensus_id=c.id)
                self.storage.add_relation(r)
        self.event_bus.publish(
            ConsensusProposed(
                consensus_id=c.id,
                content=c.content,
                proposed_at=c.created_at,
                related_message_ids=related_message_ids,
            )
        )
        return c

    def confirm_consensus(self, consensus_id: str) -> Consensus | None:
        c = self.storage.update_consensus_status(
            consensus_id, ConsensusStatus.confirmed
        )
        if c:
            self.event_bus.publish(
                ConsensusConfirmed(consensus_id=c.id, confirmed_at=_utcnow())
            )
        return c

    def deprecate_consensus(self, consensus_id: str) -> Consensus | None:
        c = self.storage.update_consensus_status(
            consensus_id, ConsensusStatus.deprecated
        )
        if c:
            self.event_bus.publish(
                ConsensusDeprecated(consensus_id=c.id, deprecated_at=_utcnow())
            )
        return c

    # ---- Relation 命令 ----

    def link_message_to_consensus(
        self, message_id: str, consensus_id: str
    ) -> Relation | None:
        if not self.storage.get_message(message_id):
            return None
        if not self.storage.get_consensus(consensus_id):
            return None
        r = Relation(message_id=message_id, consensus_id=consensus_id)
        self.storage.add_relation(r)
        self.event_bus.publish(
            MessageLinkedToConsensus(
                relation_id=r.id,
                message_id=r.message_id,
                consensus_id=r.consensus_id,
            )
        )
        return r

    def unlink_message_from_consensus(self, relation_id: str) -> bool:
        ok = self.storage.remove_relation(relation_id)
        if ok:
            self.event_bus.publish(
                MessageUnlinkedFromConsensus(
                    relation_id=relation_id,
                    message_id="",
                    consensus_id="",
                )
            )
        return ok
