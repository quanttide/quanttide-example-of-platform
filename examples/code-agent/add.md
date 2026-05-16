# code-agent — 意图对齐约束设计

## opencode.json 约束能力

opencode.json 可配置以下内容（来源：opencode.ai/docs）：

### 1. 权限控制（permission）

每个工具可设为 `allow`（自动运行）、`ask`（每次询问）、`deny`（禁止）。

影响范围按工具划分：

| 权限键 | 控制的工具 | 支持按输入细粒度匹配 |
|--------|-----------|-------------------|
| `read` | 读文件 | ✅ 按文件路径 |
| `edit` | 写、改、patch | ✅ 按文件路径 |
| `bash` | 执行命令 | ✅ 按命令（含参数） |
| `glob` | 文件搜索 | ✅ 按模式 |
| `grep` | 内容搜索 | ✅ 按正则 |
| `webfetch` | 网络请求 | ✅ 按 URL |
| `task` | 启动子 agent | ✅ 按 agent 类型 |
| `question` | 向用户提问 | ❌ 只能全局 |

例：bash 命令按模式区分权限：

```json
"permission": {
  "bash": {
    "*": "ask",
    "git *": "allow",
    "npm *": "allow",
    "rm *": "deny"
  }
}
```

### 2. 自定义 agent

可定义专门的 agent，指定独立提示词、模型、权限和工具集。

```json
"agent": {
  "code-agent": {
    "description": "执行代码任务前先确认理解",
    "prompt": "{file:./prompts/code-agent-prompt.txt}",
    "permission": {
      "edit": "ask"
    }
  }
}
```

agent 可通过 `.opencode/agents/` 目录下的 markdown 文件定义，文件名即 agent 名。

### 3. 自定义命令（command）

将重复任务固化为模板命令：

```json
"command": {
  "plan-first": {
    "template": "先输出你对任务的理解和计划，等确认后再执行。任务：$ARGUMENTS",
    "description": "先计划后执行"
  }
}
```

### 4. 外部指令文件（instructions）

可指定多个外部文件作为系统指令，支持 glob 模式：

```json
"instructions": [
  "AGENTS.md",
  ".opencode/rules/*.md"
]
```

### 5. 自定义工具（tools）

可全局禁用某些工具：

```json
"tools": {
  "write": false,
  "bash": false
}
```

## 各机制实际约束力

| 机制 | 约束力 | 实现方式 |
|------|--------|---------|
| permission | 高 | 工具执行前由系统阻断，不可跳过 |
| agent 限制 | 高 | 限定工具集和行为模式，系统级 |
| command | 中 | 模板引导，但 AI 可偏离 |
| instructions | 中 | 作为系统指令读入，但无执行阻断 |
| AGENTS.md | 中 | AI 读取，但违反无自动阻断 |
| Skills | 高 | 步骤缺失工作流终止 |

## 对照 PRD 需求：Opencode 默认机制够不够

| PRD 需求 | Opencode 能做到的 | 做不到的 |
|----------|-----------------|---------|
| R1 执行前理解确认 | 可用 Plan mode（工具只读），或自定义 agent 限制编辑权限 | 无法强制"输出理解→等待确认→再执行"这个交互顺序。权限系统只能禁工具，不能规定先做什么再做什么 |
| R2 执行中可中途纠正 | agent 可设 `steps` 限制迭代次数 | 没有内置检查点机制。`steps` 只是截断，不是有意义的暂停点 |
| R3 交付前自检 | 无 | 没有"对照验收标准验证产出"的内置步骤 |
| R4 方向变更保留上下文 | 会话历史已保留，agent 能看到之前说了什么 | 没有机制强制 agent 在方向变更时系统性地重新锚定理解 |
| R5 过程可审计 | `/share` 可分享会话链接 | 没有结构化的决策日志（当时理解了什么、为什么选这个方案、中途调整了什么） |

## 还需要额外做什么

### 需要额外工作的

| 需求 | 缺什么 | 可能的实现方式 |
|------|--------|--------------|
| R1 + R2 | 交互顺序约束（先理解→确认→执行→检查点→继续） | Skill 定义完整工作流步骤，强制不可跳步 |
| R3 | 产出验证步骤 | Skill 中增加"自检"步骤，或自定义 prompt 要求交付前输出验证清单 |
| R5 | 结构化决策日志 | 人工规范留存。Opencode 无内置能力 |

### 不需要额外工作的

| 需求 | 原因 |
|------|------|
| R4 上下文保留 | 会话历史已由 Opencode 管理，方向变更时直接利用即可 |

### 总结

Opencode 的 permission + agent + instructions 能解决"什么能做、什么不能做"的问题（工具级约束），但解决不了"先做什么、再做什么"的问题（流程级约束）。

5 条需求中，R4 可直接利用现有机制实现，R1/R2/R3 需要流程约束（Skill 或自定义 prompt），R5 需要人工规范。

核心缺口是：**Opencode 的约束机制全是"能不能"（工具权限），不是"该不该现在做"（流程编排）。** 探索性任务需要的正是后者——不是限制 AI 的能力，是规定它的工作顺序。

---

## 跳出 Opencode：流程约束方案

Opencode 没有流程编排能力。以下方案不依赖 Opencode 自身，独立实现。

### 方案 A：文件系统协议

用文件系统的存在/不存在作为流程状态信号。AI 通过读写约定路径的文件来推进流程。

```
.process/
├── understanding.md   ← AI 写入：对任务的理解
├── confirmed.flag     ← 用户创建：确认理解，AI 可执行
├── checkpoint-001.md  ← AI 写入：执行中状态摘要
├── checkpoint-002.md
├── verification.md    ← AI 写入：自检结果
└── done.flag          ← 用户创建：验收通过
```

规则：AI 在 `confirmed.flag` 出现前不能写业务文件，只能写 `understanding.md`。检查点文件存在后才能继续下一步。

优点：完全透明，用户用文件管理器即可查看状态。与 asset-agent 的设计理念一致（文件系统即信号总线）。

缺点：需要人工创建/删除 flag 文件。需要 AGENTS.md 或 instructions 定义规则。

### 方案 B：Shell 包装器

一个简单的 shell 脚本将任务拆为多阶段调用：

```bash
# phase 1: 理解
opencode run "任务：$TASK。只输出你对任务的理解，不要执行任何操作。" > .process/understanding.md
echo "确认理解后按 Enter..."
read
# phase 2: 执行
opencode run "根据之前确认的理解执行。理解见 .process/understanding.md"
echo "执行完成。按 Enter 进入验证..."
read
# phase 3: 验证
opencode run "对照 .process/understanding.md 中的验收标准，验证产出并报告差异。"
```

优点：流程由脚本强制，不可跳步。每阶段独立调用，方向变更只需重新执行当前阶段。Opencode 本身不需要任何配置。

缺点：每阶段启动新会话，上下文不连续。需要 terminal 操作。

### 方案 C：混合（文件协议 + 单会话内约束）

在 AGENTS.md 或 agent prompt 中定义流程规则，配合文件系统信号：

```
规则：
1. 在 .process/confirmed.flag 存在之前，只允许写 .process/understanding.md
2. .process/understanding.md 写完后，用 question 工具让用户确认
3. 确认后，每完成一个主要步骤，在 .process/ 下写 checkpoint 文件
4. 所有业务文件写完后，写 .process/verification.md 对照验收标准自检
5. 在所有 checkpoint 和 verification 完成前，不允许使用 task 工具启动子 agent
```

优点：单会话内完成，上下文连续。文件系统提供审计痕迹。

缺点：约束依赖 AI 遵守 prompt 规则，没有系统级阻断。

### 方案对比

| 维度 | A 文件协议 | B Shell 包装器 | C 混合 |
|------|-----------|--------------|-------|
| 流程强制力 | 中（规则约束） | 高（脚本控制） | 中（规则约束） |
| 上下文连续性 | 连续 | 分段 | 连续 |
| 审计痕迹 | ✅ 完整 | ❌ 每阶段独立 | ✅ 完整 |
| 实现成本 | 低（加规则） | 中（写脚本） | 低（改 prompt） |
| 方向变更代价 | 低（删 flag） | 低（重跑阶段） | 低（继续会话） |
