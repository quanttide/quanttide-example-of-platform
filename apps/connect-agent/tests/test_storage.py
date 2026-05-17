"""测试 JSON 存储层。"""

from app.models import Consensus, ConsensusStatus, Message, Relation, Role
from app.storage import Storage


class TestStorage:
    def test_add_and_get_message(self, storage: Storage) -> None:
        msg = Message(content="hello", role=Role.user)
        storage.add_message(msg)
        got = storage.get_message(msg.id)
        assert got is not None
        assert got.content == "hello"

    def test_list_messages_empty(self, storage: Storage) -> None:
        assert storage.list_messages() == []

    def test_list_messages(self, storage: Storage) -> None:
        storage.add_message(Message(content="a", role=Role.user))
        storage.add_message(Message(content="b", role=Role.agent))
        assert len(storage.list_messages()) == 2

    def test_update_message(self, storage: Storage) -> None:
        msg = Message(content="original", role=Role.user)
        storage.add_message(msg)
        updated = storage.update_message(msg.id, "edited")
        assert updated is not None
        assert updated.content == "edited"
        assert updated.updated_at is not None

    def test_update_message_not_found(self, storage: Storage) -> None:
        assert storage.update_message("nonexistent", "x") is None

    def test_add_and_get_consensus(self, storage: Storage) -> None:
        c = Consensus(content="共识")
        storage.add_consensus(c)
        got = storage.get_consensus(c.id)
        assert got is not None
        assert got.content == "共识"

    def test_list_consensuses_by_status(self, storage: Storage) -> None:
        storage.add_consensus(Consensus(content="a"))
        storage.add_consensus(Consensus(content="b", status=ConsensusStatus.confirmed))
        assert len(storage.list_consensuses(ConsensusStatus.proposed)) == 1
        assert len(storage.list_consensuses(ConsensusStatus.confirmed)) == 1

    def test_update_consensus_status(self, storage: Storage) -> None:
        c = Consensus(content="test")
        storage.add_consensus(c)
        storage.update_consensus_status(c.id, ConsensusStatus.confirmed)
        assert storage.get_consensus(c.id).status == ConsensusStatus.confirmed

    def test_update_consensus_status_not_found(self, storage: Storage) -> None:
        assert storage.update_consensus_status("x", ConsensusStatus.confirmed) is None

    def test_relation_crud(self, storage: Storage) -> None:
        r = Relation(message_id="m1", consensus_id="c1")
        storage.add_relation(r)
        assert len(storage.get_relations_for_consensus("c1")) == 1
        assert storage.remove_relation(r.id) is True
        assert len(storage.get_relations_for_consensus("c1")) == 0

    def test_relation_not_found(self, storage: Storage) -> None:
        assert storage.remove_relation("nonexistent") is False

    def test_get_relations_for_message(self, storage: Storage) -> None:
        storage.add_relation(Relation(message_id="m1", consensus_id="c1"))
        storage.add_relation(Relation(message_id="m1", consensus_id="c2"))
        storage.add_relation(Relation(message_id="m2", consensus_id="c1"))
        assert len(storage.get_relations_for_message("m1")) == 2
        assert len(storage.get_relations_for_message("m2")) == 1

    def test_persistence(self, storage: Storage, tmp_path: str) -> None:
        msg = Message(content="persistent", role=Role.user)
        storage.add_message(msg)
        storage2 = Storage(tmp_path)
        assert len(storage2.list_messages()) == 1
        assert storage2.get_message(msg.id).content == "persistent"

    def test_empty_file_handling(self, tmp_path: str) -> None:
        with open(tmp_path, "w") as f:
            f.write("")
        s = Storage(tmp_path)
        assert s.list_messages() == []

    def test_corrupted_file_returns_empty(self, tmp_path: str) -> None:
        with open(tmp_path, "w") as f:
            f.write("{invalid")
        s = Storage(tmp_path)
        assert s.list_messages() == []
        assert s.list_consensuses() == []
