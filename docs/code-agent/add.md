# code-agent — Plugin 架构决策

## 决策

**用 Opencode Plugin 实现算法层约束**（A1-A3 + R4 + R5）。`tool.execute.before` 系统级拦截是唯一不可跳过的约束路径，A/B/C 方案依赖 prompt 遵守，不具备同等强制力。

## 钩子责任分配

每个需求由唯一的主钩子负责，辅助钩子只做数据支撑：

| 需求 | 主钩子 | 职责 | 是否需要持久化 |
|------|--------|------|--------------|
| A1 理解披露 | `tool.execute.before` | 在 `edit`/`write` 前拦截，检查理解是否已确认 | 是（`process/understanding.json`） |
| A2 检查点 | `tool.execute.after` | `edit`/`write`/`bash` 后写入检查点文件 | 是（`process/checkpoints/`） |
| A3 自检 | 自定义工具 | AI 调用 `submit-verification`，对照理解逐项验证 | 是（`process/verification.json`） |
| R4 方向变更 | `experimental.session.compacting` | 注入当前任务状态到压缩 prompt | 否（运行时注入） |
| R5 审计 | `tool.execute.after` | 归集所有工具调用记录 | 是（`process/audit.jsonl`） |
| U1-U3 UI | 无 | ❌ 非 Plugin 能力范围 | — |

## 数据流

### 正常流程

```
AI 调用 submit-understanding
    ↓
[user 确认理解]
    ↓
AI 调用 edit/write
    ↓
tool.execute.before ──→ 读取 understanding.json，检查 confirmed
    ├── 未确认 → throw Error，阻断
    └── 已确认 → 放行
             ↓
         工具执行
             ↓
tool.execute.after ───→ 写入 audit.jsonl + 检查点
```

### 方向变更流程

```
user 说"方向不对"
    ↓
AI 重读 understanding.json
    ↓
LLM 生成新理解 → submit-understanding 覆盖旧文件
    ↓
user 确认 → 继续
```

### 压缩流程

```
会话长度超限 → 触发压缩
    ↓
experimental.session.compacting ──→ 读取当前 understanding + 检查点
    ↓
注入到 context
    ↓
LLM 生成包含完整任务状态的摘要
```

## 状态设计

### 状态分类

| 状态 | 生命周期 | 存储 | 读写方 |
|------|---------|------|--------|
| understanding | 跨检查点 | 文件 | AI（写），钩子（读） |
| checkpoints | 只追加 | 文件 | 钩子（写），压缩钩子（读） |
| audit | 只追加 | 文件 | 钩子（写） |
| verified | 单次 | 文件 | AI（写） |

### 理解确认机制

理解不是"一步到位"的——user 确认前 AI 不写业务文件，但可以读文件、调 `submit-understanding` 修改理解。

```
状态机：
理解提交（submit-understanding） → 等待确认（confirmed=false）
    ↓ user 确认（或修改后确认）
理解已确认（confirmed=true） → AI 可写文件
    ↓ 方向变更
理解被覆盖（新的 submit-understanding） → 回到等待确认
```

确认方式：`question` 工具让 user 在会话内直接确认，或 user 手动修改 `process/understanding.json` 的 `confirmed` 字段。

### 检查点编号策略

按自然数递增：`001.json`、`002.json`。每次 `tool.execute.after` 触发时，取当前最大序号 +1。无需清理历史。

## 自定义工具

提供两个自定义工具，作为 AI 与 Plugin 的协议接口：

| 工具 | 调用方 | 写入 | 效果 |
|------|--------|------|------|
| `submit-understanding` | AI | `process/understanding.json` | 记录当前任务理解，清空 `confirmed` |
| `submit-verification` | AI | `process/verification.json` | 记录自检结果，自动对比验收标准 |

AI **不能绕过这两个工具**沟通理解——文件系统是唯一的协议通道。Plugin 不解析 AI 的对话输出，只读文件。

## 压缩策略

`experimental.session.compacting` 注入三段内容到压缩上下文：

1. **当前理解**：`process/understanding.json` 的完整内容
2. **最近的检查点**：最后 3 个检查点摘要
3. **状态指示**：当前处于哪个阶段（理解/执行/验证）

不注入审计日志（体积大、压缩不需要）。

## 持久化策略

所有持久化数据放在 `.quanttide/code/` 目录下，该目录加入 `.gitignore`：

| 文件 | 写入时机 | 格式 |
|------|---------|------|
| `understanding.json` | AI 调用 `submit-understanding` | JSON |
| `checkpoints/001.json` | `tool.execute.after` 触发 | JSON |
| `audit.jsonl` | `tool.execute.after` 触发 | JSONL（每行一条） |
| `verification.json` | AI 调用 `submit-verification` | JSON |

## 边界

**Plugin 覆盖**：A1 理解披露、A2 检查点、A3 自检、R4 方向变更、R5 审计。

**Plugin 不覆盖**：U1 理解面板、U2 进度面板、U3 审计面板。UI 需要消费 `.quanttide/code/` 下的结构化数据独立实现。

**协议先行**：`.quanttide/code/` 数据格式是 UI 和 Plugin 的契约。Plugin 先定格式，UI 只需读文件，不需要改 Plugin。
