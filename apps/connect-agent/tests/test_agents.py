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
        self.agent.api_key = "test-key"

    def test_consensus_summary_empty(self) -> None:
        summary = self.agent.get_consensus_summary([])
        assert "暂无已确认的共识" in summary

    def test_consensus_summary_with_items(self) -> None:
        consensuses = [{"content": "用 PostgreSQL"}, {"content": "Python 后端"}]
        summary = self.agent.get_consensus_summary(consensuses)
        assert "用 PostgreSQL" in summary
        assert "Python 后端" in summary

    @patch("requests.post")
    def test_reply_sends_correct_prompt(self, mock_post: MagicMock) -> None:
        mock_post.return_value.ok = True
        mock_post.return_value.json.return_value = {
            "choices": [{"message": {"content": "好的，就用 PostgreSQL。"}}]
        }

        reply = self.agent.reply(
            user_message="用什么数据库？",
            history=[{"role": "user", "content": "之前聊过什么"}],
            confirmed_consensuses=[{"content": "用 PostgreSQL"}],
        )

        sent_payload = mock_post.call_args[1]["json"]
        system_msg = sent_payload["messages"][0]["content"]
        assert "用 PostgreSQL" in system_msg
        assert "消息智能体" in system_msg
        assert reply == "好的，就用 PostgreSQL。"

    @patch("requests.post")
    def test_reply_without_history(self, mock_post: MagicMock) -> None:
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

    def test_parse_action_full(self) -> None:
        block = """
action: propose
content: 使用 PostgreSQL 作为数据库
related_messages: ["msg1", "msg2"]
"""
        agent = ConsensusAgent.__new__(ConsensusAgent)
        result = agent._parse_action(block)
        assert result is not None
        assert result["action"] == "propose"
        assert result["content"] == "使用 PostgreSQL 作为数据库"
        assert result["related_messages"] == ["msg1", "msg2"]

    def test_parse_action_minimal(self) -> None:
        block = "action: confirm\ncontent: 确认结论\n"
        agent = ConsensusAgent.__new__(ConsensusAgent)
        result = agent._parse_action(block)
        assert result["action"] == "confirm"
        assert result["content"] == "确认结论"

    def test_parse_action_missing_action(self) -> None:
        block = "content: 测试"
        agent = ConsensusAgent.__new__(ConsensusAgent)
        assert agent._parse_action(block) is None

    def test_parse_action_related_messages_json(self) -> None:
        block = 'action: propose\ncontent: 测试\nrelated_messages: ["a", "b"]\n'
        agent = ConsensusAgent.__new__(ConsensusAgent)
        result = agent._parse_action(block)
        assert result["related_messages"] == ["a", "b"]

    def test_parse_action_related_messages_quoted(self) -> None:
        block = 'action: propose\ncontent: test\nrelated_messages: "x" "y"'
        agent = ConsensusAgent.__new__(ConsensusAgent)
        result = agent._parse_action(block)
        assert result["related_messages"] is not None
        assert "x" in result["related_messages"]


class TestConsensusAgentExecute:
    """共识智能体：指令执行（依赖存储和命令层）。"""

    def test_execute_propose(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        msg = conv.send_message("用 PostgreSQL", Role.user)
        agent._execute(
            {
                "action": "propose",
                "content": "使用 PostgreSQL",
                "related_messages": [msg.id],
            }
        )
        consensuses = storage.list_consensuses(ConsensusStatus.proposed)
        assert len(consensuses) == 1
        assert consensuses[0].content == "使用 PostgreSQL"
        rels = storage.get_relations_for_consensus(consensuses[0].id)
        assert len(rels) == 1
        assert rels[0].message_id == msg.id

    def test_execute_confirm(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        c = conv.propose_consensus("使用 PostgreSQL", [])
        agent._execute({"action": "confirm", "content": "使用 PostgreSQL"})
        updated = storage.get_consensus(c.id)
        assert updated.status == ConsensusStatus.confirmed

    def test_execute_confirm_no_match(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        c = conv.propose_consensus("使用 PostgreSQL", [])
        agent._execute({"action": "confirm", "content": "完全不同的内容"})
        assert storage.get_consensus(c.id).status == ConsensusStatus.proposed

    def test_execute_deprecate(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        c = conv.propose_consensus("使用 PostgreSQL", [])
        conv.confirm_consensus(c.id)
        agent._execute({"action": "deprecate", "content": "使用 PostgreSQL"})
        assert storage.get_consensus(c.id).status == ConsensusStatus.deprecated

    def test_execute_deprecate_no_match(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        c = conv.propose_consensus("使用 PostgreSQL", [])
        conv.confirm_consensus(c.id)
        agent._execute({"action": "deprecate", "content": "不存在的共识"})
        assert storage.get_consensus(c.id).status == ConsensusStatus.confirmed


class TestConsensusAgentObserve:
    """共识智能体：观察流程（mock LLM 返回）。"""

    def test_observe_propose(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        with patch("requests.post") as mock_post:
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

            user_msg = conv.send_message("我们用 PostgreSQL", Role.user)
            agent_msg = conv.send_message("好的，就用 PostgreSQL", Role.agent)
            agent.observe(user_msg, agent_msg, [])

        consensuses = storage.list_consensuses(ConsensusStatus.proposed)
        assert len(consensuses) == 1
        assert "PostgreSQL" in consensuses[0].content

    def test_observe_no_action(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        with patch("requests.post") as mock_post:
            mock_post.return_value.ok = True
            mock_post.return_value.json.return_value = {
                "choices": [{"message": {"content": "[NO_ACTION]"}}]
            }

            user_msg = conv.send_message("今天天气不错", Role.user)
            agent_msg = conv.send_message("是啊，挺好的", Role.agent)
            agent.observe(user_msg, agent_msg, [])

        assert len(storage.list_consensuses()) == 0

    def test_observe_with_proposed_context(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        conv.propose_consensus("用 PostgreSQL", [])
        with patch("requests.post") as mock_post:
            mock_post.return_value.ok = True
            mock_post.return_value.json.return_value = {
                "choices": [{"message": {"content": "[NO_ACTION]"}}]
            }

            user_msg = conv.send_message("继续讨论", Role.user)
            agent_msg = conv.send_message("好的", Role.agent)
            agent.observe(user_msg, agent_msg, [])

        sent_payload = mock_post.call_args[1]["json"]
        ctx = sent_payload["messages"][-1]["content"]
        assert "待确认的共识" in ctx
        assert "用 PostgreSQL" in ctx

    def test_observe_with_confirmed_context(self, storage: Storage) -> None:
        conv = Conversation(storage)
        agent = ConsensusAgent(conv)
        agent.api_key = "test-key"

        c = conv.propose_consensus("用 PostgreSQL", [])
        conv.confirm_consensus(c.id)
        with patch("requests.post") as mock_post:
            mock_post.return_value.ok = True
            mock_post.return_value.json.return_value = {
                "choices": [{"message": {"content": "[NO_ACTION]"}}]
            }

            user_msg = conv.send_message("继续讨论", Role.user)
            agent_msg = conv.send_message("好的", Role.agent)
            agent.observe(user_msg, agent_msg, [])

        sent_payload = mock_post.call_args[1]["json"]
        ctx = sent_payload["messages"][-1]["content"]
        assert "已确认的共识" in ctx
        assert "用 PostgreSQL" in ctx
