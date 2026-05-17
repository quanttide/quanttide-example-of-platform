"""
SQLite 存储层。

Message、Consensus、Relation 各存为独立表，共用单个 SQLite 数据库文件。
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import Any

from app.models import Consensus, ConsensusStatus, Message, Relation


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


DB_PATH = "connect.db"


class Storage:
    """SQLite 文件存储，三表共用。"""

    def __init__(self, path: str = DB_PATH) -> None:
        self._db = sqlite3.connect(path)
        self._db.row_factory = sqlite3.Row
        self._init_tables()

    def _init_tables(self) -> None:
        self._db.executescript("""
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                role TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT
            );
            CREATE TABLE IF NOT EXISTS consensuses (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'proposed',
                created_at TEXT NOT NULL,
                updated_at TEXT
            );
            CREATE TABLE IF NOT EXISTS relations (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                consensus_id TEXT NOT NULL
            );
        """)

    def _to_message(self, row: sqlite3.Row) -> Message:
        return Message(**dict(row))

    def _to_consensus(self, row: sqlite3.Row) -> Consensus:
        return Consensus(**dict(row))

    def _to_relation(self, row: sqlite3.Row) -> Relation:
        return Relation(**dict(row))

    # ---- Message ----

    def add_message(self, msg: Message) -> Message:
        d = msg.model_dump(mode="json")
        self._db.execute(
            "INSERT INTO messages (id, content, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (d["id"], d["content"], d["role"], d["created_at"], d.get("updated_at")),
        )
        self._db.commit()
        return msg

    def get_message(self, message_id: str) -> Message | None:
        row = self._db.execute(
            "SELECT * FROM messages WHERE id = ?", (message_id,)
        ).fetchone()
        return self._to_message(row) if row else None

    def list_messages(self) -> list[Message]:
        return [
            self._to_message(r)
            for r in self._db.execute(
                "SELECT * FROM messages ORDER BY created_at"
            ).fetchall()
        ]

    def update_message(self, message_id: str, new_content: str) -> Message | None:
        cur = self._db.execute(
            "UPDATE messages SET content = ?, updated_at = ? WHERE id = ?",
            (new_content, _utcnow(), message_id),
        )
        self._db.commit()
        if cur.rowcount == 0:
            return None
        return self.get_message(message_id)

    # ---- Consensus ----

    def add_consensus(self, c: Consensus) -> Consensus:
        d = c.model_dump(mode="json")
        self._db.execute(
            "INSERT INTO consensuses (id, content, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (d["id"], d["content"], d["status"], d["created_at"], d.get("updated_at")),
        )
        self._db.commit()
        return c

    def get_consensus(self, consensus_id: str) -> Consensus | None:
        row = self._db.execute(
            "SELECT * FROM consensuses WHERE id = ?", (consensus_id,)
        ).fetchone()
        return self._to_consensus(row) if row else None

    def list_consensuses(
        self, status: ConsensusStatus | None = None
    ) -> list[Consensus]:
        if status:
            rows = self._db.execute(
                "SELECT * FROM consensuses WHERE status = ? ORDER BY created_at",
                (status.value,),
            ).fetchall()
        else:
            rows = self._db.execute(
                "SELECT * FROM consensuses ORDER BY created_at"
            ).fetchall()
        return [self._to_consensus(r) for r in rows]

    def update_consensus_status(
        self, consensus_id: str, status: ConsensusStatus
    ) -> Consensus | None:
        cur = self._db.execute(
            "UPDATE consensuses SET status = ?, updated_at = ? WHERE id = ?",
            (status.value, _utcnow(), consensus_id),
        )
        self._db.commit()
        if cur.rowcount == 0:
            return None
        return self.get_consensus(consensus_id)

    # ---- Relation ----

    def add_relation(self, r: Relation) -> Relation:
        d = r.model_dump(mode="json")
        self._db.execute(
            "INSERT INTO relations (id, message_id, consensus_id) VALUES (?, ?, ?)",
            (d["id"], d["message_id"], d["consensus_id"]),
        )
        self._db.commit()
        return r

    def remove_relation(self, relation_id: str) -> bool:
        cur = self._db.execute("DELETE FROM relations WHERE id = ?", (relation_id,))
        self._db.commit()
        return cur.rowcount > 0

    def get_relations_for_consensus(self, consensus_id: str) -> list[Relation]:
        rows = self._db.execute(
            "SELECT * FROM relations WHERE consensus_id = ?", (consensus_id,)
        ).fetchall()
        return [self._to_relation(r) for r in rows]

    def get_relations_for_message(self, message_id: str) -> list[Relation]:
        rows = self._db.execute(
            "SELECT * FROM relations WHERE message_id = ?", (message_id,)
        ).fetchall()
        return [self._to_relation(r) for r in rows]
