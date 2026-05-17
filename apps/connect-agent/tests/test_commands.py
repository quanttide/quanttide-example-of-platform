"""测试命令层与事件总线。"""

from app.commands import Conversation, EventBus
from app.events import DomainEvent
from app.models import Role
from app.storage import Storage


class TestEventBus:
    def test_publish(self) -> None:
        bus = EventBus()
        received: list[DomainEvent] = []

        def handler(event: DomainEvent) -> None:
            received.append(event)

        bus.register(handler)
        bus.publish(MessageSentFixture("mid", "hi", "user"))
        assert len(received) == 1


class MessageSentFixture(DomainEvent):
    def __init__(self, mid: str, content: str, role: str) -> None:
        self.message_id = mid
        self.content = content
        self.role = role


class TestConversation:
    def setup_method(self) -> None:
        import tempfile

        self.tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        self.path = self.tmp.name
        self.tmp.close()
        self.storage = Storage(self.path)
        self.events: list[DomainEvent] = []
        self.bus = EventBus()
        self.bus.register(self.events.append)
        self.conv = Conversation(self.storage, self.bus)

    def teardown_method(self) -> None:
        import os

        if os.path.exists(self.path):
            os.unlink(self.path)

    # ---- Message 命令 ----

    def test_send_message(self) -> None:
        msg = self.conv.send_message("你好", Role.user)
        assert msg.content == "你好"
        assert msg.role == Role.user
        # 事件
        assert any(
            e.message_id == msg.id for e in self.events if hasattr(e, "message_id")
        )

    def test_edit_message(self) -> None:
        msg = self.conv.send_message("original", Role.user)
        updated = self.conv.edit_message(msg.id, "edited")
        assert updated is not None
        assert updated.content == "edited"

    def test_edit_message_not_found(self) -> None:
        assert self.conv.edit_message("nonexistent", "x") is None

    # ---- Consensus 命令 ----

    def test_propose_consensus(self) -> None:
        msg = self.conv.send_message("我们用 Python", Role.user)
        c = self.conv.propose_consensus("使用 Python", [msg.id])
        assert c.status.value == "proposed"
        rels = self.storage.get_relations_for_consensus(c.id)
        assert len(rels) == 1
        assert rels[0].message_id == msg.id

    def test_propose_with_invalid_message(self) -> None:
        c = self.conv.propose_consensus("测试", ["nonexistent"])
        # 不存在的消息不会创建 relation
        rels = self.storage.get_relations_for_consensus(c.id)
        assert len(rels) == 0

    def test_confirm_consensus(self) -> None:
        c = self.conv.propose_consensus("共识", [])
        confirmed = self.conv.confirm_consensus(c.id)
        assert confirmed is not None
        assert confirmed.status.value == "confirmed"

    def test_confirm_not_found(self) -> None:
        assert self.conv.confirm_consensus("nonexistent") is None

    def test_deprecate_consensus(self) -> None:
        c = self.conv.propose_consensus("共识", [])
        self.conv.confirm_consensus(c.id)
        deprecated = self.conv.deprecate_consensus(c.id)
        assert deprecated is not None
        assert deprecated.status.value == "deprecated"

    # ---- Relation 命令 ----

    def test_link_message_to_consensus(self) -> None:
        msg = self.conv.send_message("test", Role.user)
        c = self.conv.propose_consensus("共识", [])
        r = self.conv.link_message_to_consensus(msg.id, c.id)
        assert r is not None
        assert r.message_id == msg.id

    def test_link_invalid_message(self) -> None:
        c = self.conv.propose_consensus("共识", [])
        assert self.conv.link_message_to_consensus("bad", c.id) is None

    def test_link_invalid_consensus(self) -> None:
        msg = self.conv.send_message("test", Role.user)
        assert self.conv.link_message_to_consensus(msg.id, "bad") is None

    def test_unlink_message_from_consensus(self) -> None:
        msg = self.conv.send_message("test", Role.user)
        c = self.conv.propose_consensus("共识", [msg.id])
        rels = self.storage.get_relations_for_consensus(c.id)
        assert self.conv.unlink_message_from_consensus(rels[0].id) is True

    def test_unlink_not_found(self) -> None:
        assert self.conv.unlink_message_from_consensus("nonexistent") is False

    # ---- 完整生命周期 ----

    def test_full_lifecycle(self) -> None:
        msg = self.conv.send_message("用 PostgreSQL", Role.user)
        c = self.conv.propose_consensus("PostgreSQL", [msg.id])
        assert c.status.value == "proposed"
        self.conv.confirm_consensus(c.id)
        assert self.storage.get_consensus(c.id).status.value == "confirmed"
        self.conv.deprecate_consensus(c.id)
        assert self.storage.get_consensus(c.id).status.value == "deprecated"
