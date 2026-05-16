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
