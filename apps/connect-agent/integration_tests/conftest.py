"""
集成测试专属 fixture：live Vault、live Agent、live Conversation。

Vault 或 LLM API 不可用时自动跳过所有集成测试。
"""

from __future__ import annotations

import os
import tempfile

import pytest
from app.commands import Conversation
from app.storage import Storage


@pytest.fixture(scope="session")
def live_config():
    """连接 Vault 获取真实配置，失败则跳过所有集成测试。"""
    try:
        from app.config import settings

        key = settings.llm_api_key.get_secret_value()
        assert len(key) > 0
        return settings
    except Exception as e:
        pytest.skip(f"Vault 不可用，跳过集成测试: {e}")


@pytest.fixture
def live_storage() -> Storage:
    """集成测试用的临时存储。"""
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    path = tmp.name
    tmp.close()
    storage = Storage(path)
    yield storage
    if os.path.exists(path):
        os.unlink(path)


@pytest.fixture
def live_conversation(live_storage: Storage) -> Conversation:
    """基于真实存储的 Conversation。"""
    return Conversation(live_storage)


@pytest.fixture
def live_msg_agent(live_config):
    """连接真实 DeepSeek API 的消息智能体。"""
    from app.agents.message_agent import MessageAgent

    agent = MessageAgent()
    return agent


@pytest.fixture
def live_con_agent(live_conversation: Conversation):
    """连接真实 DeepSeek API 的共识智能体。"""
    from app.agents.consensus_agent import ConsensusAgent

    return ConsensusAgent(live_conversation)
