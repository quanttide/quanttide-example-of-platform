"""
connect-agent — 人机沟通共识引擎

基于双智能体架构（System 1 + System 2），从对话中自动提炼并维护共识。

运行方式：
    uv run python -m app.main
"""

from __future__ import annotations

import argparse
import shlex

from quanttide_connect.models import Role
from quanttide_connect.services.consensus import ConsensusService
from quanttide_connect.services.message import MessageService
from quanttide_connect.services.relation import RelationService

from app.agents.consensus_agent import ConsensusAgent
from app.agents.message_agent import MessageAgent
from app.storage import Storage


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="connect-agent REPL")
    parser.add_argument("--data", default="connect.db", help="SQLite 数据库路径")
    args = parser.parse_args(argv)

    storage = Storage(args.data)
    msg_svc = MessageService(storage)
    con_svc = ConsensusService(storage)
    rel_svc = RelationService(storage)
    msg_agent = MessageAgent()
    con_agent = ConsensusAgent(storage, con_svc, rel_svc)

    history: list[dict] = []

    print("connect-agent REPL — 输入消息开始对话，输入 /help 查看命令")
    print("=" * 50)

    while True:
        try:
            raw = input(">>> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n再见。")
            break

        if not raw:
            continue

        if raw.startswith("/"):
            parts = shlex.split(raw)
            cmd = parts[0].lower()

            if cmd in ("/quit", "/exit"):
                print("再见。")
                break

            elif cmd == "/help":
                print("""命令列表：
  /quit              退出
  /messages          查看所有消息
  /consensuses       查看所有共识
  /confirm <id>      确认共识
  /deprecate <id>    废弃共识
  /history           查看对话历史
  /help              显示此帮助""")

            elif cmd == "/messages":
                for m in storage.list_messages():
                    print(f"  [{m.id[:8]}] {m.role.value}: {m.content[:60]}...")

            elif cmd == "/consensuses":
                for c in storage.list_consensuses():
                    rels = storage.get_relations_for_consensus(c.id)
                    msg_ids = ", ".join(r.message_id[:8] for r in rels)
                    print(f"  [{c.id[:8]}] {c.status.value}: {c.content[:60]}")
                    if msg_ids:
                        print(f"         ↳ 消息: {msg_ids}")

            elif cmd == "/confirm" and len(parts) >= 2:
                c = con_svc.confirm(parts[1])
                if c:
                    print(f"已确认共识 [{c.id[:8]}]: {c.content[:60]}...")
                else:
                    print("未找到该共识")

            elif cmd == "/deprecate" and len(parts) >= 2:
                c = con_svc.deprecate(parts[1])
                if c:
                    print(f"已废弃共识 [{c.id[:8]}]: {c.content[:60]}...")
                else:
                    print("未找到该共识")

            elif cmd == "/history":
                for h in history[-10:]:
                    print(f"  {h['role']}: {h['content'][:80]}...")

            else:
                print(f"未知命令: {cmd}")

            continue

        user_msg = msg_svc.send(raw, Role.user)
        history.append({"role": "user", "content": raw})

        print("  [消息智能体思考中...]", end=" ", flush=True)
        confirmed = [
            {"content": c.content, "id": c.id}
            for c in storage.list_consensuses()
            if c.status.value == "confirmed"
        ]
        reply_text = msg_agent.reply(raw, history[:-1], confirmed)
        print("✓")

        agent_msg = msg_svc.send(reply_text, Role.agent)
        history.append({"role": "assistant", "content": reply_text})

        print(f"  {reply_text}")

        print("  [共识智能体观察中...]", end=" ", flush=True)
        con_agent.observe(user_msg, agent_msg, history)
        print()


if __name__ == "__main__":
    import sys

    main(argv=sys.argv[1:])
