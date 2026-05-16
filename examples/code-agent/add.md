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
