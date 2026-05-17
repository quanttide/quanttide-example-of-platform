"""测试命令层：补全 EventHandler 协议分支和边界。"""

from app.commands import Conversation, EventBus
from app.events import DomainEvent
from app.models import Role
from app.storage import Storage


class _EventHandlerImpl:
    """实现 EventHandler 协议（有 .handle 方法）的测试桩。"""

    def __init__(self) -> None:
        self.events: list[DomainEvent] = []

    def handle(self, event: DomainEvent) -> None:
        self.events.append(event)


class _Event(DomainEvent):
    def __init__(self, message_id: str) -> None:
        self.message_id = message_id


class TestEventBus:
    def test_publish_with_protocol_handler(self) -> None:
        """注册 EventHandler 协议对象 → 走 h.handle(event) 分支。"""
        bus = EventBus()
        handler = _EventHandlerImpl()
        bus.register(handler)
        bus.publish(_Event("msg-1"))
        assert len(handler.events) == 1

    def test_publish_with_callable(self) -> None:
        """注册普通 callable → 走 else h(event) 分支。"""
        bus = EventBus()
        received: list[DomainEvent] = []

        def handler(event: DomainEvent) -> None:
            received.append(event)

        bus.register(handler)
        bus.publish(_Event("msg-2"))
        assert len(received) == 1

    def test_publish_multiple_handlers(self) -> None:
        """多个 handler 都收到事件。"""
        bus = EventBus()
        h1 = _EventHandlerImpl()
        h2 = _EventHandlerImpl()

        def h3(event: DomainEvent) -> None:
            pass

        bus.register(h1)
        bus.register(h2)
        bus.register(h3)
        bus.publish(_Event("x"))
        assert len(h1.events) == 1
        assert len(h2.events) == 1


class TestConversation:
    def test_send_message(self, storage: Storage) -> None:
        events: list[DomainEvent] = []
        bus = EventBus()
        bus.register(events.append)
        conv = Conversation(storage, bus)

        msg = conv.send_message("你好", Role.user)
        assert msg.content == "你好"
        assert msg.role == Role.user
        assert any(e.message_id == msg.id for e in events if hasattr(e, "message_id"))

    def test_edit_message(self, conversation: Conversation) -> None:
        msg = conversation.send_message("original", Role.user)
        updated = conversation.edit_message(msg.id, "edited")
        assert updated is not None
        assert updated.content == "edited"

    def test_edit_message_not_found(self, conversation: Conversation) -> None:
        assert conversation.edit_message("nonexistent", "x") is None

    def test_propose_consensus(self, storage: Storage) -> None:
        conv = Conversation(storage)
        msg = conv.send_message("我们用 Python", Role.user)
        c = conv.propose_consensus("使用 Python", [msg.id])
        assert c.status.value == "proposed"
        rels = storage.get_relations_for_consensus(c.id)
        assert len(rels) == 1
        assert rels[0].message_id == msg.id

    def test_propose_with_invalid_message(self, storage: Storage) -> None:
        conv = Conversation(storage)
        c = conv.propose_consensus("测试", ["nonexistent"])
        rels = storage.get_relations_for_consensus(c.id)
        assert len(rels) == 0

    def test_confirm_consensus(self, conversation: Conversation) -> None:
        c = conversation.propose_consensus("共识", [])
        confirmed = conversation.confirm_consensus(c.id)
        assert confirmed is not None
        assert confirmed.status.value == "confirmed"

    def test_confirm_not_found(self, conversation: Conversation) -> None:
        assert conversation.confirm_consensus("nonexistent") is None

    def test_deprecate_consensus(self, conversation: Conversation) -> None:
        c = conversation.propose_consensus("共识", [])
        conversation.confirm_consensus(c.id)
        deprecated = conversation.deprecate_consensus(c.id)
        assert deprecated is not None
        assert deprecated.status.value == "deprecated"

    def test_link_message_to_consensus(self, storage: Storage) -> None:
        conv = Conversation(storage)
        msg = conv.send_message("test", Role.user)
        c = conv.propose_consensus("共识", [])
        r = conv.link_message_to_consensus(msg.id, c.id)
        assert r is not None
        assert r.message_id == msg.id

    def test_link_invalid_message(self, storage: Storage) -> None:
        conv = Conversation(storage)
        c = conv.propose_consensus("共识", [])
        assert conv.link_message_to_consensus("bad", c.id) is None

    def test_link_invalid_consensus(self, storage: Storage) -> None:
        conv = Conversation(storage)
        msg = conv.send_message("test", Role.user)
        assert conv.link_message_to_consensus(msg.id, "bad") is None

    def test_unlink_message_from_consensus(self, storage: Storage) -> None:
        conv = Conversation(storage)
        msg = conv.send_message("test", Role.user)
        c = conv.propose_consensus("共识", [msg.id])
        rels = storage.get_relations_for_consensus(c.id)
        assert conv.unlink_message_from_consensus(rels[0].id) is True

    def test_unlink_not_found(self, conversation: Conversation) -> None:
        assert conversation.unlink_message_from_consensus("nonexistent") is False

    def test_full_lifecycle(self, storage: Storage) -> None:
        conv = Conversation(storage)
        msg = conv.send_message("用 PostgreSQL", Role.user)
        c = conv.propose_consensus("PostgreSQL", [msg.id])
        assert c.status.value == "proposed"
        conv.confirm_consensus(c.id)
        assert storage.get_consensus(c.id).status.value == "confirmed"
        conv.deprecate_consensus(c.id)
        assert storage.get_consensus(c.id).status.value == "deprecated"
