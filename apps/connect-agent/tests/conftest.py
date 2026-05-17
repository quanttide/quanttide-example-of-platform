"""
共享 fixture：临时存储、事件收集器。

供 tests/ 下所有单元测试使用。
"""

from __future__ import annotations

import os
import tempfile
from collections.abc import Callable
from typing import Any

import pytest
from app.commands import Conversation, EventBus
from app.events import DomainEvent
from app.storage import Storage


@pytest.fixture
def tmp_path() -> str:
    """返回临时 JSON 文件路径，测试结束后自动清理。"""
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    path = tmp.name
    tmp.close()
    yield path
    if os.path.exists(path):
        os.unlink(path)


@pytest.fixture
def storage(tmp_path: str) -> Storage:
    """基于临时文件的 Storage 实例。"""
    return Storage(tmp_path)


@pytest.fixture
def event_bus() -> EventBus:
    """事件总线 + 事件收集器。"""
    bus = EventBus()
    collected: list[DomainEvent] = []
    bus.register(collected.append)
    return bus, collected


@pytest.fixture
def conversation(storage: Storage) -> Conversation:
    """基于临时存储的 Conversation 实例。"""
    return Conversation(storage)
