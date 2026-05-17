"""
JSON 文件存储层。

将 Message、Consensus、Relation 持久化到单个 JSON 文件，
满足 DRD "可直接映射为 JSON 文件"的要求。
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.models import Consensus, ConsensusStatus, Message, Relation


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Storage:
    """JSON 文件存储，三表合一。"""

    def __init__(self, path: str | Path = "data.json") -> None:
        self.path = Path(path)
        self._messages: list[dict[str, Any]] = []
        self._consensuses: list[dict[str, Any]] = []
        self._relations: list[dict[str, Any]] = []
        self._load()

    # ---- 内部序列化 ----

    def _load(self) -> None:
        if self.path.exists():
            text = self.path.read_text().strip()
            if text:
                try:
                    raw = json.loads(text)
                except json.JSONDecodeError:
                    self._messages = []
                    self._consensuses = []
                    self._relations = []
                    return
                self._messages = raw.get("messages", [])
                self._consensuses = raw.get("consensuses", [])
                self._relations = raw.get("relations", [])
        else:
            self._messages = []
            self._consensuses = []
            self._relations = []

    def _save(self) -> None:
        self.path.write_text(
            json.dumps(
                {
                    "messages": self._messages,
                    "consensuses": self._consensuses,
                    "relations": self._relations,
                },
                indent=2,
                default=str,
            )
        )

    # ---- Message ----

    def add_message(self, msg: Message) -> Message:
        self._messages.append(msg.model_dump(mode="json"))
        self._save()
        return msg

    def get_message(self, message_id: str) -> Message | None:
        for d in self._messages:
            if d["id"] == message_id:
                return Message(**d)
        return None

    def list_messages(self) -> list[Message]:
        return [Message(**d) for d in self._messages]

    def update_message(self, message_id: str, new_content: str) -> Message | None:
        for d in self._messages:
            if d["id"] == message_id:
                d["content"] = new_content
                now = _utcnow()
                d["updated_at"] = now.isoformat()
                self._save()
                return Message(**d)
        return None

    # ---- Consensus ----

    def add_consensus(self, c: Consensus) -> Consensus:
        self._consensuses.append(c.model_dump(mode="json"))
        self._save()
        return c

    def get_consensus(self, consensus_id: str) -> Consensus | None:
        for d in self._consensuses:
            if d["id"] == consensus_id:
                return Consensus(**d)
        return None

    def list_consensuses(
        self, status: ConsensusStatus | None = None
    ) -> list[Consensus]:
        result = [Consensus(**d) for d in self._consensuses]
        if status:
            result = [c for c in result if c.status == status]
        return result

    def update_consensus_status(
        self, consensus_id: str, status: ConsensusStatus
    ) -> Consensus | None:
        for d in self._consensuses:
            if d["id"] == consensus_id:
                d["status"] = status.value
                now = _utcnow()
                d["updated_at"] = now.isoformat()
                self._save()
                return Consensus(**d)
        return None

    # ---- Relation ----

    def add_relation(self, r: Relation) -> Relation:
        self._relations.append(r.model_dump(mode="json"))
        self._save()
        return r

    def remove_relation(self, relation_id: str) -> bool:
        before = len(self._relations)
        self._relations = [r for r in self._relations if r["id"] != relation_id]
        if len(self._relations) < before:
            self._save()
            return True
        return False

    def get_relations_for_consensus(self, consensus_id: str) -> list[Relation]:
        return [
            Relation(**r) for r in self._relations if r["consensus_id"] == consensus_id
        ]

    def get_relations_for_message(self, message_id: str) -> list[Relation]:
        return [Relation(**r) for r in self._relations if r["message_id"] == message_id]
