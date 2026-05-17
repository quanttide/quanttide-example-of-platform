"""测试智能体业务逻辑（mock LLM API）。"""

from unittest.mock import MagicMock, patch

from app.agents.consensus_agent import ConsensusAgent
from app.agents.message_agent import MessageAgent
from app.storage import Storage
from quanttide_connect.models import ConsensusStatus, Role
from quanttide_connect.services.consensus import ConsensusService
from quanttide_connect.services.relation import RelationService


class TestMessageAgent:
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
            user_message="你好", history=[], confirmed_consensuses=[]
        )
        assert reply == "你好！"


class TestConsensusAgentParse:
    def test_parse_action_full(self) -> None:
        block = 'action: propose\ncontent: PostgreSQL\nrelated_messages: ["msg1"]\n'
        agent = ConsensusAgent.__new__(ConsensusAgent)
        result = agent._parse_action(block)
        assert result["action"] == "propose"
        assert result["content"] == "PostgreSQL"
        assert result["related_messages"] == ["msg1"]

    def test_parse_action_minimal(self) -> None:
        agent = ConsensusAgent.__new__(ConsensusAgent)
        result = agent._parse_action("action: confirm\ncontent: 确认结论\n")
        assert result["action"] == "confirm"
        assert result["content"] == "确认结论"

    def test_parse_action_missing_action(self) -> None:
        agent = ConsensusAgent.__new__(ConsensusAgent)
        assert agent._parse_action("content: 测试") is None

    def test_parse_action_related_messages_json(self) -> None:
        agent = ConsensusAgent.__new__(ConsensusAgent)
        result = agent._parse_action(
            'action: propose\ncontent: test\nrelated_messages: ["a", "b"]\n'
        )
        assert result["related_messages"] == ["a", "b"]

    def test_parse_action_related_messages_quoted(self) -> None:
        agent = ConsensusAgent.__new__(ConsensusAgent)
        result = agent._parse_action(
            'action: propose\ncontent: test\nrelated_messages: "x" "y"'
        )
        assert "x" in result["related_messages"]


class TestConsensusAgentExecute:
    def test_execute_propose(self, storage: Storage) -> None:
        con_svc = ConsensusService(storage)
        rel_svc = RelationService(storage)
        agent = ConsensusAgent(storage, con_svc, rel_svc)
        agent.api_key = "test-key"
        agent._execute(
            {"action": "propose", "content": "使用 PostgreSQL", "related_messages": []}
        )
        consensuses = storage.list_consensuses(ConsensusStatus.proposed)
        assert len(consensuses) == 1

    def test_execute_confirm(self, storage: Storage) -> None:
        con_svc = ConsensusService(storage)
        rel_svc = RelationService(storage)
        agent = ConsensusAgent(storage, con_svc, rel_svc)
        agent.api_key = "test-key"
        c = con_svc.propose("使用 PostgreSQL")
        agent._execute({"action": "confirm", "content": "使用 PostgreSQL"})
        assert storage.get_consensus(c.id).status == ConsensusStatus.confirmed

    def test_execute_confirm_no_match(self, storage: Storage) -> None:
        con_svc = ConsensusService(storage)
        rel_svc = RelationService(storage)
        agent = ConsensusAgent(storage, con_svc, rel_svc)
        agent.api_key = "test-key"
        c = con_svc.propose("使用 PostgreSQL")
        agent._execute({"action": "confirm", "content": "其他内容"})
        assert storage.get_consensus(c.id).status == ConsensusStatus.proposed

    def test_execute_deprecate(self, storage: Storage) -> None:
        con_svc = ConsensusService(storage)
        rel_svc = RelationService(storage)
        agent = ConsensusAgent(storage, con_svc, rel_svc)
        agent.api_key = "test-key"
        c = con_svc.propose("使用 PostgreSQL")
        con_svc.confirm(c.id)
        agent._execute({"action": "deprecate", "content": "使用 PostgreSQL"})
        assert storage.get_consensus(c.id).status == ConsensusStatus.deprecated

    def test_execute_deprecate_no_match(self, storage: Storage) -> None:
        con_svc = ConsensusService(storage)
        rel_svc = RelationService(storage)
        agent = ConsensusAgent(storage, con_svc, rel_svc)
        agent.api_key = "test-key"
        c = con_svc.propose("使用 PostgreSQL")
        con_svc.confirm(c.id)
        agent._execute({"action": "deprecate", "content": "不存在的共识"})
        assert storage.get_consensus(c.id).status == ConsensusStatus.confirmed


class TestConsensusAgentObserve:
    def test_observe_propose(self, storage: Storage) -> None:
        from unittest.mock import patch

        con_svc = ConsensusService(storage)
        rel_svc = RelationService(storage)
        agent = ConsensusAgent(storage, con_svc, rel_svc)
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
            from quanttide_connect.models import Message

            user_msg = Message(content="我们用 PostgreSQL", role=Role.user)
            agent_msg = Message(content="好的", role=Role.agent)
            agent.observe(user_msg, agent_msg, [])

        consensuses = storage.list_consensuses(ConsensusStatus.proposed)
        assert len(consensuses) >= 1

    def test_observe_no_action(self, storage: Storage) -> None:
        from unittest.mock import patch

        con_svc = ConsensusService(storage)
        rel_svc = RelationService(storage)
        agent = ConsensusAgent(storage, con_svc, rel_svc)
        agent.api_key = "test-key"

        with patch("requests.post") as mock_post:
            mock_post.return_value.ok = True
            mock_post.return_value.json.return_value = {
                "choices": [{"message": {"content": "[NO_ACTION]"}}]
            }
            from quanttide_connect.models import Message

            user_msg = Message(content="今天天气不错", role=Role.user)
            agent_msg = Message(content="是啊", role=Role.agent)
            agent.observe(user_msg, agent_msg, [])

        assert len(storage.list_consensuses()) == 0
