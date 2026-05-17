"""
领域事件与事件总线。
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime
from typing import Protocol


class DomainEvent:
    """领域事件基类。"""


class MessageSent(DomainEvent):
    def __init__(
        self, message_id: str, content: str, role: str, timestamp: datetime
    ) -> None:
        self.message_id = message_id
        self.content = content
        self.role = role
        self.timestamp = timestamp


class MessageEdited(DomainEvent):
    def __init__(self, message_id: str, new_content: str, updated_at: datetime) -> None:
        self.message_id = message_id
        self.new_content = new_content
        self.updated_at = updated_at


class ConsensusProposed(DomainEvent):
    def __init__(
        self,
        consensus_id: str,
        content: str,
        proposed_at: datetime,
        related_message_ids: list[str],
    ) -> None:
        self.consensus_id = consensus_id
        self.content = content
        self.proposed_at = proposed_at
        self.related_message_ids = related_message_ids


class ConsensusConfirmed(DomainEvent):
    def __init__(self, consensus_id: str, confirmed_at: datetime) -> None:
        self.consensus_id = consensus_id
        self.confirmed_at = confirmed_at


class ConsensusDeprecated(DomainEvent):
    def __init__(self, consensus_id: str, deprecated_at: datetime) -> None:
        self.consensus_id = consensus_id
        self.deprecated_at = deprecated_at


class MessageLinkedToConsensus(DomainEvent):
    def __init__(self, relation_id: str, message_id: str, consensus_id: str) -> None:
        self.relation_id = relation_id
        self.message_id = message_id
        self.consensus_id = consensus_id


class MessageUnlinkedFromConsensus(DomainEvent):
    def __init__(self, relation_id: str, message_id: str, consensus_id: str) -> None:
        self.relation_id = relation_id
        self.message_id = message_id
        self.consensus_id = consensus_id


class EventHandler(Protocol):
    def handle(self, event: DomainEvent) -> None: ...


class EventBus:
    """事件总线。"""

    def __init__(self) -> None:
        self._handlers: list[EventHandler | Callable[[DomainEvent], None]] = []

    def register(self, handler: EventHandler | Callable[[DomainEvent], None]) -> None:
        self._handlers.append(handler)

    def publish(self, event: DomainEvent) -> None:
        for h in self._handlers:
            if hasattr(h, "handle"):
                h.handle(event)
            else:
                h(event)
