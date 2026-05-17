"""完整对话生命周期：真实 LLM 调用，验证共识被正确提炼。"""

from __future__ import annotations

from app.storage import Storage
from quanttide_connect.models import ConsensusStatus, Role
from quanttide_connect.services.consensus import ConsensusService
from quanttide_connect.services.message import MessageService
from quanttide_connect.services.relation import RelationService


class TestExplicitTrigger:
    """用户说"记下来" → 共识被 propose。"""

    def test_user_says_write_it_down(
        self,
        live_storage: Storage,
        live_msg_svc: MessageService,
        live_con_svc: ConsensusService,
        live_rel_svc: RelationService,
        live_msg_agent,
        live_con_agent,
    ) -> None:
        conv_storage = live_storage
        msg_svc = live_msg_svc
        con_svc = live_con_svc
        history: list[dict] = []

        user_msg = msg_svc.send("记下来，我们用 PostgreSQL 作为主数据库", Role.user)
        history.append({"role": "user", "content": user_msg.content})

        confirmed = [
            {"content": c.content, "id": c.id}
            for c in conv_storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed)
        agent_msg = msg_svc.send(reply, Role.agent)
        history.append({"role": "assistant", "content": reply})

        live_con_agent.observe(user_msg, agent_msg, history)

        proposed = conv_storage.list_consensuses(ConsensusStatus.proposed)
        assert len(proposed) >= 1
        assert any("PostgreSQL" in c.content for c in proposed)


class TestNoTrigger:
    """聊天气 → 无共识生成。"""

    def test_small_talk_no_consensus(
        self,
        live_storage: Storage,
        live_msg_svc: MessageService,
        live_con_svc: ConsensusService,
        live_rel_svc: RelationService,
        live_msg_agent,
        live_con_agent,
    ) -> None:
        msg_svc = live_msg_svc
        history: list[dict] = []

        user_msg = msg_svc.send("今天天气不错", Role.user)
        history.append({"role": "user", "content": user_msg.content})

        confirmed = [
            {"content": c.content, "id": c.id}
            for c in live_storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed)
        agent_msg = msg_svc.send(reply, Role.agent)
        history.append({"role": "assistant", "content": reply})

        live_con_agent.observe(user_msg, agent_msg, history)

        assert len(live_storage.list_consensuses()) == 0


class TestConsensusFlow:
    """propose → confirm → deprecate。"""

    def test_user_confirms_and_deprecates(
        self,
        live_storage: Storage,
        live_msg_svc: MessageService,
        live_con_svc: ConsensusService,
        live_rel_svc: RelationService,
        live_msg_agent,
        live_con_agent,
    ) -> None:
        msg_svc = live_msg_svc
        con_svc = live_con_svc
        history: list[dict] = []

        user_msg = msg_svc.send("确定用 PostgreSQL，记下来", Role.user)
        history.append({"role": "user", "content": user_msg.content})

        confirmed = [
            {"content": c.content, "id": c.id}
            for c in live_storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed)
        agent_msg = msg_svc.send(reply, Role.agent)
        history.append({"role": "assistant", "content": reply})

        live_con_agent.observe(user_msg, agent_msg, history)

        proposed = live_storage.list_consensuses(ConsensusStatus.proposed)
        assert len(proposed) >= 1

        con_svc.confirm(proposed[0].id)
        confirmed = live_storage.list_consensuses(ConsensusStatus.confirmed)
        assert len(confirmed) >= 1

        user_msg = msg_svc.send("算了，不用 PostgreSQL 了，改为 MySQL", Role.user)
        history.append({"role": "user", "content": user_msg.content})

        confirmed_list = [
            {"content": c.content, "id": c.id}
            for c in live_storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed_list)
        agent_msg = msg_svc.send(reply, Role.agent)
        history.append({"role": "assistant", "content": reply})

        live_con_agent.observe(user_msg, agent_msg, history)

        deprecated = live_storage.list_consensuses(ConsensusStatus.deprecated)
        proposed_new = live_storage.list_consensuses(ConsensusStatus.proposed)
        assert len(deprecated) >= 1 or len(proposed_new) >= 1


class TestAgentRemembersConsensus:
    """已有共识时 → 回复应自然提及。"""

    def test_reply_references_consensus(
        self,
        live_storage: Storage,
        live_msg_svc: MessageService,
        live_con_svc: ConsensusService,
        live_rel_svc: RelationService,
        live_msg_agent,
        live_con_agent,
    ) -> None:
        msg_svc = live_msg_svc
        con_svc = live_con_svc

        c = con_svc.propose("使用 PostgreSQL 作为主数据库")
        con_svc.confirm(c.id)

        user_msg = msg_svc.send("我们用什么数据库？", Role.user)
        history = [{"role": "user", "content": user_msg.content}]

        confirmed = [
            {"content": c.content, "id": c.id}
            for c in live_storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply = live_msg_agent.reply(user_msg.content, history[:-1], confirmed)
        assert "PostgreSQL" in reply, f"回复应提及已有共识，实际回复: {reply}"
