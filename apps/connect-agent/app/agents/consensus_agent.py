"""
共识智能体（System 2 — 慢思考）

职责：观察对话，提炼共识，维护共识卡片库。不与人类直接对话。
"""

from __future__ import annotations

import json
import re

from app.config import settings
from app.models import ConsensusStatus, Message
from app.services.consensus import ConsensusService
from app.services.relation import RelationService
from app.storage import Storage

CONSENSUS_SYSTEM_PROMPT = """你是 connect-agent 的共识智能体（System 2 — 慢思考）。

你的角色是观察对话，提炼共识，维护共识卡片库。你**不与人类直接对话**。

## 核心职责
- 持续观察消息流，感知共识的形成
- 决定何时提炼共识（显性触发 + 隐性感知）
- 输出结构化指令，而非面向用户的自然语言

## 输出格式
当你判断需要提炼或更新共识时，输出以下格式的指令：

```
[CONSENSUS_ACTION]
action: propose | confirm | deprecate
content: 共识的具体内容
related_messages: ["消息ID1", "消息ID2"]
[/CONSENSUS_ACTION]
```

- `propose` — 从若干消息中提炼一个新的共识（提议状态）
- `confirm` — 确认一个已有提议的共识
- `deprecate` — 废弃一个不再适用的共识

## 判断标准（自然结晶）
- 人类明确说"记下来"、"确认这个结论"、"总结一下"等 → 立即提炼
- AI 回复中自然带出了总结性陈述 → 自动提炼
- 同一话题经过多轮讨论后趋于稳定 → 可提炼
"""


class ConsensusAgent:
    """异步观察对话、提炼共识的智能体。"""

    def __init__(
        self,
        storage: Storage,
        consensus_svc: ConsensusService,
        relation_svc: RelationService,
    ) -> None:
        self.storage = storage
        self.consensus_svc = consensus_svc
        self.relation_svc = relation_svc
        self.api_key = settings.llm_api_key.get_secret_value()
        self.base_url = "https://api.deepseek.com"

    def observe(
        self, user_message: Message, agent_message: Message, history: list[dict]
    ) -> None:
        """观察一轮对话，判断是否需要操作共识。"""
        import requests

        confirmed = self.storage.list_consensuses(ConsensusStatus.confirmed)
        proposed = self.storage.list_consensuses(ConsensusStatus.proposed)

        ctx = f"## 本轮用户消息\n{user_message.content}\n\n## 本轮 AI 回复\n{agent_message.content}\n\n"
        if confirmed:
            ctx += (
                "## 已确认的共识\n"
                + "\n".join(f"- {c.content}" for c in confirmed)
                + "\n\n"
            )
        if proposed:
            ctx += (
                "## 待确认的共识（proposed）\n"
                + "\n".join(f"- {c.content} (id: {c.id})" for c in proposed)
                + "\n\n"
            )

        ctx += "基于以上对话，如果有必要，输出共识操作指令。如果不需要，输出 [NO_ACTION]。\n"

        messages = [
            {"role": "system", "content": CONSENSUS_SYSTEM_PROMPT},
            *history[-6:],
            {"role": "user", "content": ctx},
        ]

        resp = requests.post(
            f"{self.base_url}/v1/chat/completions",
            headers={"Authorization": f"Bearer {self.api_key}"},
            json={
                "model": "deepseek-v4-flash",
                "messages": messages,
                "stream": False,
            },
            timeout=60,
        )
        resp.raise_for_status()
        output = resp.json()["choices"][0]["message"]["content"]

        self._handle_instructions(output)

    def _handle_instructions(self, output: str) -> None:
        if "[NO_ACTION]" in output or "[/CONSENSUS_ACTION]" not in output:
            return
        blocks = re.findall(
            r"\[CONSENSUS_ACTION\](.*?)\[/CONSENSUS_ACTION\]", output, re.DOTALL
        )
        for block in blocks:
            action = self._parse_action(block)
            if action:
                self._execute(action)

    def _parse_action(self, block: str) -> dict | None:
        action: dict = {}
        for line in block.strip().splitlines():
            line = line.strip()
            if line.startswith("action:"):
                action["action"] = line.split(":", 1)[1].strip()
            elif line.startswith("content:"):
                action["content"] = line.split(":", 1)[1].strip()
            elif line.startswith("related_messages:"):
                raw = line.split(":", 1)[1].strip()
                try:
                    action["related_messages"] = json.loads(raw)
                except json.JSONDecodeError:
                    action["related_messages"] = re.findall(r'"([^"]+)"', raw)
        if "action" in action:
            return action
        return None

    def _execute(self, action: dict) -> None:
        act = action.get("action")
        content = action.get("content", "")
        related = action.get("related_messages", [])
        con_svc = self.consensus_svc
        rel_svc = self.relation_svc

        if act == "propose" and content:
            c = con_svc.propose(content, related)
            print(f"[共识] 提议: {c.content[:60]}... (id: {c.id})")

        elif act == "confirm":
            proposed = self.storage.list_consensuses(ConsensusStatus.proposed)
            for pc in proposed:
                if content and content in pc.content:
                    con_svc.confirm(pc.id)
                    print(f"[共识] 确认: {pc.content[:60]}...")
                    return
            print(f"[共识] 确认指令未匹配到待确认的共识: {content[:40]}...")

        elif act == "deprecate":
            confirmed = self.storage.list_consensuses(ConsensusStatus.confirmed)
            for cc in confirmed:
                if content and content in cc.content:
                    con_svc.deprecate(cc.id)
                    print(f"[共识] 废弃: {cc.content[:60]}...")
                    return
            print(f"[共识] 废弃指令未匹配到已确认的共识: {content[:40]}...")
