"""
数据模型：Message、Consensus、Relation

严格对应 DRD 定义，无冗余字段。
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum

from pydantic import BaseModel, Field


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _new_id() -> str:
    return uuid.uuid4().hex[:12]


class Role(str, Enum):
    user = "user"
    agent = "agent"
    system = "system"


class Message(BaseModel):
    """对话消息，按时间排序。"""

    id: str = Field(default_factory=_new_id)
    content: str
    role: Role
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime | None = None


class ConsensusStatus(str, Enum):
    proposed = "proposed"
    confirmed = "confirmed"
    deprecated = "deprecated"


class Consensus(BaseModel):
    """从消息中提炼出的共识。"""

    id: str = Field(default_factory=_new_id)
    content: str
    status: ConsensusStatus = ConsensusStatus.proposed
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime | None = None


class Relation(BaseModel):
    """消息与共识之间的多对多溯源关联。"""

    id: str = Field(default_factory=_new_id)
    message_id: str
    consensus_id: str
