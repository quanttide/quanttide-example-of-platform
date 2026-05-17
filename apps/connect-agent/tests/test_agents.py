"""测试智能体业务逻辑（mock LLM API）。"""

from unittest.mock import MagicMock, patch

from app.agents.consensus_agent import ConsensusAgent
from app.agents.message_agent import MessageAgent
from app.commands import Conversation
from app.models import ConsensusStatus, Role
from app.storage import Storage

# ===== Message Agent (System 1) =====


class TestMessageAgent:
    """消息智能体：验证共识摘要注入和回复处理。"""

    def setup_method(self) -> None:
        self.agent = MessageAgent()
        # patch api_key to avoid Vault dependency in tests
        self.agent.api_key = "test-key"

    def test_consensus_summary_empty(self) -> None:
        """无共识时摘要应提示"暂无"。"""
        summary = self.agent.get_consensus_summary([])
        assert "暂无已确认的共识" in summary

    def test_consensus_summary_with_items(self) -> None:
        """有共识时列出内容。"""
        consensuses = [{"content": "用 PostgreSQL"}, {"content": "Python 后端"}]
        summary = self.agent.get_consensus_summary(consensuses)
        assert "用 PostgreSQL" in summary
        assert "Python 后端" in summary

    @patch("requests.post")
    def test_reply_sends_correct_prompt(self, mock_post: MagicMock) -> None:
        """回复时 system prompt 包含共识摘要。"""
        mock_post.return_value.ok = True
        mock_post.return_value.json.return_value = {
            "choices": [{"message": {"content": "好的，就用 PostgreSQL。"}}]
        }

        reply = self.agent.reply(
            user_message="用什么数据库？",
            history=[{"role": "user", "content": "之前聊过什么"}],
            confirmed_consensuses=[{"content": "用 PostgreSQL"}],
        )

        # 验证 system prompt 包含共识
        sent_payload = mock_post.call_args[1]["json"]
        system_msg = sent_payload["messages"][0]["content"]
        assert "用 PostgreSQL" in system_msg
        assert "消息智能体" in system_msg

        # 验证回复正确返回
        assert reply == "好的，就用 PostgreSQL。"

    @patch("requests.post")
    def test_reply_without_history(self, mock_post: MagicMock) -> None:
        """无历史消息时也能正常回复。"""
        mock_post.return_value.ok = True
        mock_post.return_value.json.return_value = {
            "choices": [{"message": {"content": "你好！"}}]
        }

        reply = self.agent.reply(
            user_message="你好",
            history=[],
            confirmed_consensuses=[],
        )
        assert reply == "你好！"


# ===== Consensus Agent (System 2) =====


class TestConsensusAgentParse:
    """共识智能体：指令解析（不依赖 LLM）。"""

    def setup_method(self) -> None:
        import tempfile

        self.tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        self.path = self.tmp.name
        self.tmp.close()
        self.storage = Storage(self.path)
        self.conv = Conversation(self.storage)
        self.agent = ConsensusAgent(self.conv)
        self.agent.api_key = "test-key"

    def teardown_method(self) -> None:
        import os

        if os.path.exists(self.path):
            os.unlink(self.path)

    def test_parse_action_full(self) -> None:
        """解析完整的指令块。"""
        block = """
action: propose
content: 使用 PostgreSQL 作为数据库
related_messages: ["msg1", "msg2"]
"""
        result = self.agent._parse_action(block)
        assert result is not None
        assert result["action"] == "propose"
        assert result["content"] == "使用 PostgreSQL 作为数据库"
        assert result["related_messages"] == ["msg1", "msg2"]

    def test_parse_action_minimal(self) -> None:
        """只含 action 的指令块。"""
        block = """
action: confirm
content: 确认结论
"""
        result = self.agent._parse_action(block)
        assert result is not None
        assert result["action"] == "confirm"
        assert result["content"] == "确认结论"
        assert "related_messages" not in result

    def test_parse_action_missing_action(self) -> None:
        """缺少 action 字段返回 None。"""
        block = """
content: 测试
related_messages: ["msg1"]
"""
        assert self.agent._parse_action(block) is None

    def test_parse_action_related_messages_json(self) -> None:
        """related_messages 支持 JSON 数组格式。"""
        block = """
action: propose
content: 测试
related_messages: ["a", "b"]
"""
        result = self.agent._parse_action(block)
        assert result["related_messages"] == ["a", "b"]

    def test_parse_action_related_messages_quoted(self) -> None:
        """也支持引号分隔的格式（非 JSON 时的 fallback）。"""
        block = 'action: propose\ncontent: test\nrelated_messages: "x" "y"'
        result = self.agent._parse_action(block)
        assert result["related_messages"] is not None
        assert "x" in result["related_messages"]


class TestConsensusAgentExecute:
    """共识智能体：指令执行（依赖存储和命令层）。"""

    def setup_method(self) -> None:
        import tempfile

        self.tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        self.path = self.tmp.name
        self.tmp.close()
        self.storage = Storage(self.path)
        self.conv = Conversation(self.storage)
        self.agent = ConsensusAgent(self.conv)
        self.agent.api_key = "test-key"

    def teardown_method(self) -> None:
        import os

        if os.path.exists(self.path):
            os.unlink(self.path)

    def test_execute_propose(self) -> None:
        """propose 指令创建共识和关联。"""
        msg = self.conv.send_message("用 PostgreSQL", Role.user)
        self.agent._execute(
            {
                "action": "propose",
                "content": "使用 PostgreSQL",
                "related_messages": [msg.id],
            }
        )
        consensuses = self.storage.list_consensuses(ConsensusStatus.proposed)
        assert len(consensuses) == 1
        assert consensuses[0].content == "使用 PostgreSQL"
        rels = self.storage.get_relations_for_consensus(consensuses[0].id)
        assert len(rels) == 1
        assert rels[0].message_id == msg.id

    def test_execute_confirm(self) -> None:
        """confirm 指令匹配并确认已存在的 proposed 共识。"""
        c = self.conv.propose_consensus("使用 PostgreSQL", [])
        assert c.status == ConsensusStatus.proposed
        self.agent._execute(
            {
                "action": "confirm",
                "content": "使用 PostgreSQL",
            }
        )
        updated = self.storage.get_consensus(c.id)
        assert updated.status == ConsensusStatus.confirmed

    def test_execute_confirm_no_match(self) -> None:
        """confirm 找不到匹配时不报错，状态不变。"""
        c = self.conv.propose_consensus("使用 PostgreSQL", [])
        self.agent._execute(
            {
                "action": "confirm",
                "content": "完全不同的内容",
            }
        )
        updated = self.storage.get_consensus(c.id)
        assert updated.status == ConsensusStatus.proposed  # 未被改变

    def test_execute_deprecate(self) -> None:
        """deprecate 指令匹配并废弃已确认的共识。"""
        c = self.conv.propose_consensus("使用 PostgreSQL", [])
        self.conv.confirm_consensus(c.id)
        self.agent._execute(
            {
                "action": "deprecate",
                "content": "使用 PostgreSQL",
            }
        )
        updated = self.storage.get_consensus(c.id)
        assert updated.status == ConsensusStatus.deprecated

    def test_execute_deprecate_no_match(self) -> None:
        """deprecate 找不到匹配时不报错。"""
        c = self.conv.propose_consensus("使用 PostgreSQL", [])
        self.conv.confirm_consensus(c.id)
        self.agent._execute(
            {
                "action": "deprecate",
                "content": "不存在的共识",
            }
        )
        updated = self.storage.get_consensus(c.id)
        assert updated.status == ConsensusStatus.confirmed  # 未被改变


class TestConsensusAgentObserve:
    """共识智能体：观察流程（mock LLM 返回）。"""

    def setup_method(self) -> None:
        import tempfile

        self.tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        self.path = self.tmp.name
        self.tmp.close()
        self.storage = Storage(self.path)
        self.conv = Conversation(self.storage)
        self.agent = ConsensusAgent(self.conv)
        self.agent.api_key = "test-key"

    def teardown_method(self) -> None:
        import os

        if os.path.exists(self.path):
            os.unlink(self.path)

    @patch("requests.post")
    def test_observe_propose(self, mock_post: MagicMock) -> None:
        """观察一轮对话，LLM 返回 propose 指令 → 共识被创建。"""
        mock_post.return_value.ok = True
        mock_post.return_value.json.return_value = {
            "choices": [
                {
                    "message": {
                        "content": """
[CONSENSUS_ACTION]
action: propose
content: 团队用 PostgreSQL
related_messages: []
[/CONSENSUS_ACTION]
"""
                    }
                }
            ]
        }

        user_msg = self.conv.send_message("我们用 PostgreSQL", Role.user)
        agent_msg = self.conv.send_message("好的，就用 PostgreSQL", Role.agent)
        self.agent.observe(user_msg, agent_msg, [])

        consensuses = self.storage.list_consensuses(ConsensusStatus.proposed)
        assert len(consensuses) == 1
        assert "PostgreSQL" in consensuses[0].content

    @patch("requests.post")
    def test_observe_no_action(self, mock_post: MagicMock) -> None:
        """LLM 返回 [NO_ACTION] → 无共识创建。"""
        mock_post.return_value.ok = True
        mock_post.return_value.json.return_value = {
            "choices": [{"message": {"content": "[NO_ACTION]"}}]
        }

        user_msg = self.conv.send_message("今天天气不错", Role.user)
        agent_msg = self.conv.send_message("是啊，挺好的", Role.agent)
        self.agent.observe(user_msg, agent_msg, [])

        assert len(self.storage.list_consensuses()) == 0

    @patch("requests.post")
    def test_observe_with_proposed_context(self, mock_post: MagicMock) -> None:
        """已存在 proposed 共识时，上下文应包含它。"""
        self.conv.propose_consensus("用 PostgreSQL", [])
        mock_post.return_value.ok = True
        mock_post.return_value.json.return_value = {
            "choices": [{"message": {"content": "[NO_ACTION]"}}]
        }

        user_msg = self.conv.send_message("继续讨论", Role.user)
        agent_msg = self.conv.send_message("好的", Role.agent)
        self.agent.observe(user_msg, agent_msg, [])

        # 验证发送给 LLM 的上下文中包含待确认的共识
        sent_payload = mock_post.call_args[1]["json"]
        ctx = sent_payload["messages"][-1]["content"]
        assert "待确认的共识" in ctx
        assert "用 PostgreSQL" in ctx

    @patch("requests.post")
    def test_observe_with_confirmed_context(self, mock_post: MagicMock) -> None:
        """已存在 confirmed 共识时，上下文应包含它。"""
        c = self.conv.propose_consensus("用 PostgreSQL", [])
        self.conv.confirm_consensus(c.id)
        mock_post.return_value.ok = True
        mock_post.return_value.json.return_value = {
            "choices": [{"message": {"content": "[NO_ACTION]"}}]
        }

        user_msg = self.conv.send_message("继续讨论", Role.user)
        agent_msg = self.conv.send_message("好的", Role.agent)
        self.agent.observe(user_msg, agent_msg, [])

        sent_payload = mock_post.call_args[1]["json"]
        ctx = sent_payload["messages"][-1]["content"]
        assert "已确认的共识" in ctx
        assert "用 PostgreSQL" in ctx
