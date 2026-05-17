# connect-agent 测试策略

## 概述

connect-agent 的测试分两层：单元测试和集成测试。分离的原因是两个智能体（System 1 + System 2）依赖外部 LLM API，如果所有测试都走真实 API，运行慢、不稳定、依赖环境。单元测试 mock 掉 LLM，验证代码逻辑；集成测试走真实 LLM，验证业务意图。

## 目录结构

```
tests/                      ← 单元测试
├── conftest.py             ← 共享 fixture
├── test_models.py          ← 数据模型
├── test_storage.py         ← JSON 存储层
├── test_commands.py        ← 命令层 + 事件总线
├── test_agents.py          ← 智能体业务逻辑（mock LLM）
└── test_main.py            ← REPL 入口

integration_tests/          ← 集成测试
├── conftest.py             ← 真实 Vault + LLM fixture
└── test_lifecycle.py       ← 验收场景
```

两种测试互不干扰。`pytest tests/` 默认跑单元测试，`pytest integration_tests/` 按需跑集成测试。

## 测试层次

### 单元测试

覆盖代码的所有执行路径，不依赖任何外部服务。三个验证维度：

#### 第一层：数据模型（test_models.py）

验证 Pydantic 模型的结构约束。

```
创建 → assert field 赋值正确
默认值 → assert ConsensusStatus.proposed
枚举 → assert Role.user / Role.agent
自动生成 → assert isinstance(msg.id, str), len(msg.id) == 12
唯一性 → assert r1.id != r2.id
空值 → assert msg.updated_at is None
```

不测 Pydantic 框架本身，只测业务约束。

#### 第二层：存储层（test_storage.py）

验证 JSON 文件的读写和持久化，每个测试用例用独立临时文件。

```
CRUD → add → get → update → remove
边界 → 空库、不存在 ID、列表过滤
持久化 → 写入后新建 Storage 读回 → 数据一致
容错 → 空文件、损坏的 JSON → 不崩溃
```

#### 第三层：命令层（test_commands.py）

验证 7 个命令的业务语义和事件发布。

```
命令 → 业务断言 + 事件断言
边界 → 无效 ID → None
生命周期 → send → propose (proposed) → confirm (confirmed) → deprecate (deprecated)
EventBus → 协议对象走 h.handle(), 普通 callable 走 h()
```

#### 第四层：智能体（test_agents.py）

 mock 掉 `requests.post`，不依赖真实 LLM。

**消息智能体：** 验证 prompt 格式、共识摘要注入、回复返回。

```
consensus_summary = self.agent.get_consensus_summary([])
                   → "暂无已确认的共识"

mock_post.return_value.json → {choices: [{message: {content: "回复"}}]}
reply = self.agent.reply(...)
sent_payload = mock_post.call_args[1]["json"]
sent_payload["messages"][0]["content"]
                   → assert "用 PostgreSQL" in system_prompt
```

**共识智能体：** 验证指令解析和执行，分三层测试：

```
_parse_action:    解析文本块 → dict（action/content/related_messages）
_execute:         解析后的 dict → 操作存储层（propose/confirm/deprecate）
observe:          mock LLM 返回 → 完整流程（解析 → 执行 → 验证存储层结果）
```

#### 第五层：入口（test_main.py）

 mock 掉 Storage、MessageAgent、ConsensusAgent，只验证 REPL 的命令分发。

```
输入 "/quit" → assert print("再见。")
输入 "/unknown" → assert print("未知命令: /unknown")
输入 "/help" → assert "/quit" 在输出中
输入 "" → 跳过，不报错
```

### 集成测试

用真实 Vault 获取 API key，走真实 DeepSeek API，验证业务意图是否实现。

#### fixture 设计

```python
# integration_tests/conftest.py

@pytest.fixture(scope="session")
def live_config():
    """Vault 不可用时跳过所有集成测试。"""
    try:
        from app.config import settings
        key = settings.llm_api_key.get_secret_value()
        return settings
    except Exception:
        pytest.skip("Vault 不可用")
```

`scope="session"` 让 Vault 连接在整个 session 中只检查一次。`live_msg_agent` 和 `live_con_agent` 是 function scope，每次测试新建。

#### 验收场景

| 测试类 | 输入 | 预期 | 对应 DRD |
|--------|------|------|---------|
| `TestExplicitTrigger` | "记下来，我们用 PostgreSQL" | 共识被 propose，内容含 PostgreSQL | "从消息中提炼共识" |
| `TestNoTrigger` | "今天天气不错" | 无共识生成 | "无关对话不产生共识" |
| `TestConsensusFlow` | 确认 → 反悔 | status: proposed → confirmed → deprecated | "共识状态流转" |
| `TestAgentRemembersConsensus` | 已有共识后问"用什么数据库" | 回复含 "PostgreSQL" | "AI 回复呼应已有共识" |

## fixture 设计决策

### 为什么 tests/conftest.py 用 fixture 函数而不是 class setup

之前三个测试类（test_storage、test_commands、test_agents）各自用 `setup_method` 创建临时文件，大量重复。用 conftest 集中后：

```
# 每个测试函数获得独立的临时存储
def test_add_and_get_message(self, storage: Storage):
    ...

# 不需要临时存储的测试不注入
def test_list_messages_empty(self, storage: Storage):
    ...
```

pytest fixture 默认 function scope，测试间隔离。需要持久化验证的测试注入 `tmp_path` 和 `storage` 两个 fixture。

### 为什么 integration_tests 不共享 tests/conftest.py

虽然 `tmp_path` 和 `storage` 逻辑相同，但集成测试 fixture 依赖 `live_config`（需要 Vault），导入链不同。分开 conftest 避免了单元测试意外引入 Vault 依赖。

## 运行方式

```bash
# 单元测试（CI 必过）
uv run pytest tests/
uv run pytest tests/ -v           # 详细输出
uv run pytest --cov=app tests/    # 带覆盖率

# 集成测试（按需运行）
uv run pytest integration_tests/
uv run pytest integration_tests/ -v

# 全部
uv run pytest tests/ integration_tests/
```

## 当前状态

| 指标 | 值 |
|------|----|
| 单元测试数 | 77 |
| 集成测试数 | 4 |
| 代码覆盖率 | 99% |
| 未覆盖 | `if __name__ == "__main__"` 保护条件、`except json.JSONDecodeError` 异常路径 |

## 设计原则

1. **目录即语义** — `tests/` 是单元测试，`integration_tests/` 是集成测试，路径本身说明类别
2. **优雅降级** — Vault 不可用时集成测试 `pytest.skip`，不报错
3. **mock 外层不改内层** — 智能体测试 mock 的是 `requests.post`，不 mock 内部逻辑，保证被测试代码是真实实现
4. **验收场景驱动** — 集成测试直接对应 DRD 业务流程，不写和单元测试重复的边界场景
