"""测试数据模型。"""

from datetime import datetime, timezone

from app.models import Consensus, ConsensusStatus, Message, Relation, Role


class TestMessage:
    def test_create(self) -> None:
        msg = Message(content="你好", role=Role.user)
        assert msg.content == "你好"
        assert msg.role == Role.user
        assert isinstance(msg.id, str)
        assert len(msg.id) == 32
        assert isinstance(msg.created_at, datetime)

    def test_default_role(self) -> None:
        msg = Message(content="test", role=Role.agent)
        assert msg.role == Role.agent

    def test_updated_at_none_by_default(self) -> None:
        msg = Message(content="test", role=Role.system)
        assert msg.updated_at is None


class TestConsensus:
    def test_create_proposed(self) -> None:
        c = Consensus(content="测试共识")
        assert c.content == "测试共识"
        assert c.status == ConsensusStatus.proposed

    def test_status_enum(self) -> None:
        c = Consensus(content="test", status=ConsensusStatus.confirmed)
        assert c.status == ConsensusStatus.confirmed

    def test_deprecated(self) -> None:
        c = Consensus(content="test", status=ConsensusStatus.deprecated)
        assert c.status == ConsensusStatus.deprecated


class TestRelation:
    def test_create(self) -> None:
        r = Relation(message_id="msg1", consensus_id="con1")
        assert r.message_id == "msg1"
        assert r.consensus_id == "con1"

    def test_unique_id(self) -> None:
        r1 = Relation(message_id="a", consensus_id="b")
        r2 = Relation(message_id="a", consensus_id="b")
        assert r1.id != r2.id
