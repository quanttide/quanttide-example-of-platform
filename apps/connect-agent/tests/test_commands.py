"""测试服务层和事件总线。"""

from app.storage import Storage
from quanttide_connect.events import EventBus
from quanttide_connect.models import Role
from quanttide_connect.services.consensus import ConsensusService
from quanttide_connect.services.message import MessageService
from quanttide_connect.services.relation import RelationService


class _Handler:
    def __init__(self) -> None:
        self.events: list = []

    def handle(self, event) -> None:
        self.events.append(event)


class TestEventBus:
    def test_publish_with_protocol_handler(self) -> None:
        bus = EventBus()
        h = _Handler()
        bus.register(h)
        bus.publish(_Event("msg-1"))
        assert len(h.events) == 1

    def test_publish_with_callable(self) -> None:
        bus = EventBus()
        received: list = []
        bus.register(received.append)
        bus.publish(_Event("msg-2"))
        assert len(received) == 1

    def test_publish_multiple_handlers(self) -> None:
        bus = EventBus()
        h1 = _Handler()
        h2 = _Handler()

        def h3(event) -> None:
            pass

        bus.register(h1)
        bus.register(h2)
        bus.register(h3)
        bus.publish(_Event("x"))
        assert len(h1.events) == 1
        assert len(h2.events) == 1


class _Event:
    def __init__(self, message_id: str) -> None:
        self.message_id = message_id


class TestMessageService:
    def test_send_message(self, storage: Storage) -> None:
        svc = MessageService(storage)
        msg = svc.send("你好", Role.user)
        assert msg.content == "你好"
        assert msg.role == Role.user

    def test_edit_message(self, storage: Storage) -> None:
        svc = MessageService(storage)
        msg = svc.send("original", Role.user)
        updated = svc.edit(msg.id, "edited")
        assert updated is not None
        assert updated.content == "edited"

    def test_edit_message_not_found(self, storage: Storage) -> None:
        svc = MessageService(storage)
        assert svc.edit("nonexistent", "x") is None


class TestConsensusService:
    def test_propose_consensus(self, storage: Storage) -> None:
        svc = ConsensusService(storage)
        msg_svc = MessageService(storage)
        msg = msg_svc.send("我们用 Python", Role.user)
        c = svc.propose("使用 Python", [msg.id])
        assert c.status.value == "proposed"
        rels = storage.get_relations_for_consensus(c.id)
        assert len(rels) == 1
        assert rels[0].message_id == msg.id

    def test_confirm_consensus(self, storage: Storage) -> None:
        svc = ConsensusService(storage)
        c = svc.propose("共识")
        confirmed = svc.confirm(c.id)
        assert confirmed is not None
        assert confirmed.status.value == "confirmed"

    def test_confirm_not_found(self, storage: Storage) -> None:
        svc = ConsensusService(storage)
        assert svc.confirm("nonexistent") is None

    def test_deprecate_consensus(self, storage: Storage) -> None:
        svc = ConsensusService(storage)
        c = svc.propose("共识")
        svc.confirm(c.id)
        deprecated = svc.deprecate(c.id)
        assert deprecated is not None
        assert deprecated.status.value == "deprecated"

    def test_full_lifecycle(self, storage: Storage) -> None:
        svc = ConsensusService(storage)
        msg_svc = MessageService(storage)
        msg_svc.send("用 PostgreSQL", Role.user)
        c = svc.propose("PostgreSQL")
        assert c.status.value == "proposed"
        svc.confirm(c.id)
        assert storage.get_consensus(c.id).status.value == "confirmed"
        svc.deprecate(c.id)
        assert storage.get_consensus(c.id).status.value == "deprecated"


class TestRelationService:
    def test_link_and_unlink(self, storage: Storage) -> None:
        rel_svc = RelationService(storage)
        msg_svc = MessageService(storage)
        con_svc = ConsensusService(storage)
        msg = msg_svc.send("test", Role.user)
        c = con_svc.propose("共识")
        r = rel_svc.link(msg.id, c.id)
        assert r is not None
        assert r.message_id == msg.id
        assert rel_svc.unlink(r.id) is True

    def test_link_invalid_message(self, storage: Storage) -> None:
        rel_svc = RelationService(storage)
        con_svc = ConsensusService(storage)
        c = con_svc.propose("共识")
        assert rel_svc.link("bad", c.id) is None

    def test_link_invalid_consensus(self, storage: Storage) -> None:
        rel_svc = RelationService(storage)
        msg_svc = MessageService(storage)
        msg = msg_svc.send("test", Role.user)
        assert rel_svc.link(msg.id, "bad") is None

    def test_unlink_not_found(self, storage: Storage) -> None:
        rel_svc = RelationService(storage)
        assert rel_svc.unlink("nonexistent") is False
