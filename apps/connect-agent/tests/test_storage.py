"""测试 JSON 存储层。"""

import os
import tempfile

from app.models import Consensus, ConsensusStatus, Message, Relation, Role
from app.storage import Storage


class TestStorage:
    def setup_method(self) -> None:
        self.tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        self.path = self.tmp.name
        self.tmp.close()
        self.storage = Storage(self.path)

    def teardown_method(self) -> None:
        if os.path.exists(self.path):
            os.unlink(self.path)

    def test_add_and_get_message(self) -> None:
        msg = Message(content="hello", role=Role.user)
        self.storage.add_message(msg)
        got = self.storage.get_message(msg.id)
        assert got is not None
        assert got.content == "hello"

    def test_list_messages_empty(self) -> None:
        assert self.storage.list_messages() == []

    def test_list_messages(self) -> None:
        self.storage.add_message(Message(content="a", role=Role.user))
        self.storage.add_message(Message(content="b", role=Role.agent))
        assert len(self.storage.list_messages()) == 2

    def test_update_message(self) -> None:
        msg = Message(content="original", role=Role.user)
        self.storage.add_message(msg)
        updated = self.storage.update_message(msg.id, "edited")
        assert updated is not None
        assert updated.content == "edited"
        assert updated.updated_at is not None

    def test_update_message_not_found(self) -> None:
        assert self.storage.update_message("nonexistent", "x") is None

    def test_add_and_get_consensus(self) -> None:
        c = Consensus(content="共识")
        self.storage.add_consensus(c)
        got = self.storage.get_consensus(c.id)
        assert got is not None
        assert got.content == "共识"

    def test_list_consensuses_by_status(self) -> None:
        self.storage.add_consensus(Consensus(content="a"))
        self.storage.add_consensus(
            Consensus(content="b", status=ConsensusStatus.confirmed)
        )
        assert len(self.storage.list_consensuses(ConsensusStatus.proposed)) == 1
        assert len(self.storage.list_consensuses(ConsensusStatus.confirmed)) == 1

    def test_update_consensus_status(self) -> None:
        c = Consensus(content="test")
        self.storage.add_consensus(c)
        self.storage.update_consensus_status(c.id, ConsensusStatus.confirmed)
        assert self.storage.get_consensus(c.id).status == ConsensusStatus.confirmed

    def test_update_consensus_status_not_found(self) -> None:
        assert (
            self.storage.update_consensus_status("x", ConsensusStatus.confirmed) is None
        )

    def test_relation_crud(self) -> None:
        r = Relation(message_id="m1", consensus_id="c1")
        self.storage.add_relation(r)
        assert len(self.storage.get_relations_for_consensus("c1")) == 1
        assert self.storage.remove_relation(r.id) is True
        assert len(self.storage.get_relations_for_consensus("c1")) == 0

    def test_relation_not_found(self) -> None:
        assert self.storage.remove_relation("nonexistent") is False

    def test_get_relations_for_message(self) -> None:
        self.storage.add_relation(Relation(message_id="m1", consensus_id="c1"))
        self.storage.add_relation(Relation(message_id="m1", consensus_id="c2"))
        self.storage.add_relation(Relation(message_id="m2", consensus_id="c1"))
        assert len(self.storage.get_relations_for_message("m1")) == 2
        assert len(self.storage.get_relations_for_message("m2")) == 1

    def test_persistence(self) -> None:
        msg = Message(content="persistent", role=Role.user)
        self.storage.add_message(msg)
        storage2 = Storage(self.path)
        assert len(storage2.list_messages()) == 1
        assert storage2.get_message(msg.id).content == "persistent"

    def test_empty_file_handling(self) -> None:
        with open(self.path, "w") as f:
            f.write("")
        s = Storage(self.path)
        assert s.list_messages() == []

    def test_corrupted_file_returns_empty(self) -> None:
        with open(self.path, "w") as f:
            f.write("{invalid")
        s = Storage(self.path)
        assert s.list_messages() == []
        assert s.list_consensuses() == []
