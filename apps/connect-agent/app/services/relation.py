"""
关联服务：消息与共识之间的多对多关联管理。
"""

from __future__ import annotations

from app.events import EventBus, MessageLinkedToConsensus, MessageUnlinkedFromConsensus
from app.models import Relation
from app.storage import Storage


class RelationService:
    def __init__(self, storage: Storage, event_bus: EventBus | None = None) -> None:
        self.storage = storage
        self.event_bus = event_bus or EventBus()

    def link(self, message_id: str, consensus_id: str) -> Relation | None:
        if not self.storage.get_message(message_id) or not self.storage.get_consensus(
            consensus_id
        ):
            return None
        r = Relation(message_id=message_id, consensus_id=consensus_id)
        self.storage.add_relation(r)
        self.event_bus.publish(
            MessageLinkedToConsensus(
                relation_id=r.id, message_id=r.message_id, consensus_id=r.consensus_id
            )
        )
        return r

    def unlink(self, relation_id: str) -> bool:
        ok = self.storage.remove_relation(relation_id)
        if ok:
            self.event_bus.publish(
                MessageUnlinkedFromConsensus(
                    relation_id=relation_id, message_id="", consensus_id=""
                )
            )
        return ok
