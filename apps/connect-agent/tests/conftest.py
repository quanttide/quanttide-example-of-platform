"""
共享 fixture：临时存储。

供 tests/ 下所有单元测试使用。
"""

from __future__ import annotations

import os
import tempfile

import pytest
from app.storage import Storage
from quanttide_connect.events import EventBus
from quanttide_connect.services.consensus import ConsensusService
from quanttide_connect.services.message import MessageService
from quanttide_connect.services.relation import RelationService


@pytest.fixture
def tmp_path() -> str:
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    path = tmp.name
    tmp.close()
    yield path
    if os.path.exists(path):
        os.unlink(path)


@pytest.fixture
def storage(tmp_path: str) -> Storage:
    return Storage(tmp_path)


@pytest.fixture
def event_bus() -> tuple[EventBus, list]:
    bus = EventBus()
    collected: list = []
    bus.register(collected.append)
    return bus, collected


@pytest.fixture
def msg_service(storage: Storage) -> MessageService:
    return MessageService(storage)


@pytest.fixture
def con_service(storage: Storage) -> ConsensusService:
    return ConsensusService(storage)


@pytest.fixture
def rel_service(storage: Storage) -> RelationService:
    return RelationService(storage)
