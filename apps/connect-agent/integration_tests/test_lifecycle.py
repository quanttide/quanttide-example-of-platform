"""完整对话生命周期：真实 LLM 调用，验证共识被正确提炼。"""

from __future__ import annotations

import pytest
from app.commands import Conversation
from app.models import ConsensusStatus, Role


class TestExplicitTrigger:
    """用户显性触发共识提炼。"""

    def test_user_says_write_it_down(
        self, live_conversation: Conversation, live_msg_agent, live_con_agent
    ) -> None:
        """用户说"记下来，我们用 PostgreSQL" → 共识被 propose。"""
        conv = live_conversation
        history: list[dict] = []

        # 用户发送消息
        user_msg = conv.send_message(
            "记下来，我们用 PostgreSQL 作为主数据库", Role.user
        )
        history.append({"role": "user", "content": user_msg.content})

        # System 1 回复
        confirmed = [
            {"content": c.content, "id": c.id}
            for c in conv.storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed)
        agent_msg = conv.send_message(reply, Role.agent)
        history.append({"role": "assistant", "content": reply})

        # System 2 观察
        live_con_agent.observe(user_msg, agent_msg, history)

        # 验证：应有 proposed 共识，内容包含 PostgreSQL
        proposed = conv.storage.list_consensuses(ConsensusStatus.proposed)
        assert len(proposed) >= 1, "应至少有一条 proposed 共识"
        assert any("PostgreSQL" in c.content for c in proposed), (
            "共识内容应包含 PostgreSQL"
        )


class TestNoTrigger:
    """无关对话不会触发共识。"""

    def test_small_talk_no_consensus(
        self, live_conversation: Conversation, live_msg_agent, live_con_agent
    ) -> None:
        """聊天气 → 无共识生成。"""
        conv = live_conversation
        history: list[dict] = []

        user_msg = conv.send_message("今天天气不错", Role.user)
        history.append({"role": "user", "content": user_msg.content})

        confirmed = [
            {"content": c.content, "id": c.id}
            for c in conv.storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed)
        agent_msg = conv.send_message(reply, Role.agent)
        history.append({"role": "assistant", "content": reply})

        live_con_agent.observe(user_msg, agent_msg, history)

        # 验证：不应有共识生成
        assert len(conv.storage.list_consensuses()) == 0, "闲聊不应生成共识"


class TestConsensusFlow:
    """完整共识生命周期：propose → confirm → deprecate。"""

    def test_user_confirms_and_deprecates(
        self, live_conversation: Conversation, live_msg_agent, live_con_agent
    ) -> None:
        """用户确认共识 → 状态为 confirmed；用户反悔 → 废弃。"""
        conv = live_conversation
        history: list[dict] = []

        # 步骤1：用户提出用 PostgreSQL
        user_msg = conv.send_message("确定用 PostgreSQL，记下来", Role.user)
        history.append({"role": "user", "content": user_msg.content})

        confirmed = [
            {"content": c.content, "id": c.id}
            for c in conv.storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed)
        agent_msg = conv.send_message(reply, Role.agent)
        history.append({"role": "assistant", "content": reply})

        live_con_agent.observe(user_msg, agent_msg, history)

        proposed = conv.storage.list_consensuses(ConsensusStatus.proposed)
        assert len(proposed) >= 1, "应有 proposed 共识"

        # 步骤2：手动确认这个共识（模拟用户确认）
        conv.confirm_consensus(proposed[0].id)
        confirmed = conv.storage.list_consensuses(ConsensusStatus.confirmed)
        assert len(confirmed) >= 1, "应有 confirmed 共识"

        # 步骤3：用户反悔
        user_msg = conv.send_message("算了，不用 PostgreSQL 了，改为 MySQL", Role.user)
        history.append({"role": "user", "content": user_msg.content})

        confirmed_list = [
            {"content": c.content, "id": c.id}
            for c in conv.storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed_list)
        agent_msg = conv.send_message(reply, Role.agent)
        history.append({"role": "assistant", "content": reply})

        live_con_agent.observe(user_msg, agent_msg, history)

        # 验证：原先的共识应被废弃，或有新的 proposed
        deprecated = conv.storage.list_consensuses(ConsensusStatus.deprecated)
        proposed_new = conv.storage.list_consensuses(ConsensusStatus.proposed)
        assert len(deprecated) >= 1 or len(proposed_new) >= 1, "应有废弃或新提议的共识"


class TestAgentRemembersConsensus:
    """消息智能体在回复中自然提及已有共识。"""

    def test_reply_references_consensus(
        self, live_conversation: Conversation, live_msg_agent, live_con_agent
    ) -> None:
        """已有 confirmed 共识时 → 回复应自然提及。"""
        conv = live_conversation
        history: list[dict] = []

        # 先建立一个共识
        conv.propose_consensus("使用 PostgreSQL 作为主数据库", [])
        c = conv.storage.list_consensuses(ConsensusStatus.proposed)[0]
        conv.confirm_consensus(c.id)

        # 发送后续问题
        user_msg = conv.send_message("我们用什么数据库？", Role.user)
        history.append({"role": "user", "content": user_msg.content})

        confirmed = [
            {"content": c.content, "id": c.id}
            for c in conv.storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed)
        # 不记入 storage（只是验证回复），强制断言回复提及共识
        assert "PostgreSQL" in reply, f"回复应提及已有共识，实际回复: {reply}"
