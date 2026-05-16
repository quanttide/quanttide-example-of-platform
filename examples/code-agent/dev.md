# code-agent — 开发指南

## 文件结构

```
.opencode/plugins/
├── package.json             # 依赖声明
├── understanding.ts         # A1: 理解披露
├── checkpoint.ts            # A2: 检查点
├── verification.ts          # A3: 自检
└── audit.ts                 # R5: 审计日志
.quanttide/code/
├── understanding.json       # 当前理解（AI 输出）
├── checkpoints/             # 检查点记录
├── audit.jsonl              # 审计日志
└── verification.json        # 自检结果
```

## Plugin 入口

每个文件导出符合 `Plugin` 类型的函数。Opencode 启动时自动加载 `.opencode/plugins/` 下所有文件。

```ts
import type { Plugin } from "@opencode-ai/plugin"

export const UnderstandingPlugin: Plugin = async (ctx) => {
  return {
    "tool.execute.before": async (input, output) => { /* ... */ },
    "tool.execute.after": async (input, output) => { /* ... */ },
    tool: { /* 自定义工具 */ },
  }
}
```

每个钩子函数接收 `(input, output)`。
- `input` — 只读的触发信息
- `output` — 可写的控制对象

### 上下文参数

```ts
async ({ project, client, $, directory, worktree }) => { }
```

- `project` — 当前项目信息
- `directory` — 工作目录
- `worktree` — git worktree 路径
- `client` — SDK 客户端（用于日志、状态查询）
- `$` — Bun shell API

## 数据结构

### 理解（understanding）

```json
{
  "task": "xxx 功能",
  "deliverable": "代码",
  "criteria": ["条件1", "条件2"],
  "assumptions": ["假设1"],
  "risks": ["风险1"]
}
```

文件 `process/understanding.json`，由 AI 通过自定义工具写入。

### 检查点（checkpoint）

```json
{
  "id": 1,
  "timestamp": "2026-05-16T10:00:00Z",
  "done": ["读取了 src/a.ts", "理解了接口签名"],
  "next": "写 src/b.ts",
  "changes": "发现需要额外处理边界情况"
}
```

文件 `process/checkpoints/001.json`、`002.json`...，由 `tool.execute.after` 自动生成。

### 审计日志（audit log）

```jsonl
{"ts":"...","tool":"read","args":{...},"result":"..."}
{"ts":"...","tool":"edit","args":{...},"result":"..."}
{"ts":"...","tool":"bash","args":{...},"result":"..."}
```

文件 `process/audit.jsonl`，每行一条记录，由 `tool.execute.after` 追加。

### 自检（verification）

```json
{
  "checks": [
    {"item": "条件1", "status": "pass"},
    {"item": "条件2", "status": "fail", "reason": "缺少 xxx"}
  ],
  "uncovered": ["额外做了 yyy"],
  "summary": "1/2 通过"
}
```

文件 `process/verification.json`，由 AI 调用自定义工具写入。

## A1: 理解披露

### 目标

AI 写任何业务文件前，必须先输出结构化理解。未输出则阻断。

### 自定义工具

供 AI 调用来提交理解：

```ts
tool: {
  "submit-understanding": tool({
    description: "提交对当前任务的结构化理解，write/edit 前必须调用",
    args: {
      task: tool.schema.string().describe("一句话描述任务"),
      deliverable: tool.schema.string().describe("交付形态：代码/文档/配置/调研报告"),
      criteria: tool.schema.array(tool.schema.string()).describe("可验证的验收条件"),
      assumptions: tool.schema.array(tool.schema.string()).describe("隐含假设"),
      risks: tool.schema.array(tool.schema.string()).describe("可能理解错的地方"),
    },
    async execute(args, ctx) {
      await Bun.write(".quanttide/code/understanding.json", JSON.stringify(args, null, 2))
      return "理解已记录，等待确认后开始执行"
    },
  }),
}
```

### 拦截钩子

`edit`/`write` 执行前检查理解是否已确认：

```ts
"tool.execute.before": async (input, output) => {
  if (input.tool !== "edit" && input.tool !== "write") return

  const under = await loadUnderstanding()
  if (!under || !under.confirmed) {
    throw new Error("必须先提交理解并等待确认后才能修改文件。调用 submit-understanding 提交理解。")
  }
}
```

### 确认机制

用户通过 `question` 工具或文件系统确认（`.quanttide/code/understanding.json` 中设 `confirmed: true`）。

## A2: 检查点

### 目标

关键工具调用后自动记录进度，暂停等待用户确认。

### 钩子

```ts
"tool.execute.after": async (input, output) => {
  if (!["edit", "write", "bash"].includes(input.tool)) return

  const id = nextCheckpointId()
  const cp = {
    id,
    timestamp: new Date().toISOString(),
    done: [`${input.tool}: ${JSON.stringify(input.args)}`],
    next: inferNext(input.tool, input.args),
    changes: [],
  }
  await Bun.write(`.quanttide/code/checkpoints/${String(id).padStart(3, "0")}.json`, JSON.stringify(cp, null, 2))
}
```

暂停通过 `permission.ask` 机制配合实现，或使用 `question` 工具向用户确认是否继续。

## A3: 自检

### 目标

AI 交付前对照原始理解逐项校验。

### 自定义工具

```ts
tool: {
  "submit-verification": tool({
    description: "提交自检结果，对照 submit-understanding 中的验收标准逐项验证",
    args: {
      checks: tool.schema.array(tool.schema.object({
        item: tool.schema.string(),
        status: tool.schema.enum(["pass", "fail"]),
        reason: tool.schema.string().optional(),
      })),
      uncovered: tool.schema.array(tool.schema.string()).describe("计划外做了或没做的"),
      summary: tool.schema.string(),
    },
    async execute(args, ctx) {
      const understanding = await loadUnderstanding()
      // 自动对比 args.checks 与 understanding.criteria
      await Bun.write(".quanttide/code/verification.json", JSON.stringify({
        ...args,
        checkedAgainst: understanding,
      }, null, 2))
      const failed = args.checks.filter(c => c.status === "fail")
      if (failed.length > 0) {
        return `自检完成，${failed.length} 项未通过:\n` +
          failed.map(c => `- ${c.item}: ${c.reason}`).join("\n")
      }
      return "自检全部通过"
    },
  }),
}
```

## R4: 方向变更

### 目标

会话压缩时不丢失上下文，尤其是当前任务状态和决策记录。

```ts
"experimental.session.compacting": async (input, output) => {
  const under = await loadUnderstanding()
  const checkpoints = await loadCheckpoints()
  output.context.push(`## code-agent 状态

### 当前任务
${JSON.stringify(under, null, 2)}

### 已完成步骤
${checkpoints.map(c => `- ${c.timestamp}: ${c.done.join(", ")}`).join("\n")}

### 下一步
${checkpoints[checkpoints.length - 1]?.next || "待定"}
`)
}
```

## R5: 审计

### 目标

记录所有工具调用，可回溯关键决策。

```ts
"tool.execute.after": async (input, output) => {
  const entry = {
    ts: new Date().toISOString(),
    tool: input.tool,
    args: input.args,
  }
  await $`echo ${JSON.stringify(entry)} >> .quanttide/code/audit.jsonl`
}
```

配合 `session.idle` 做定期冲刷（如每条记录立即写盘则不需要）。

## 开发步骤

1. **初始化 Plugin 目录**

```
mkdir -p .opencode/plugins
```

2. **安装依赖**

在 `.opencode/` 下创建 `package.json`，添加 `@opencode-ai/plugin` 依赖：

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "latest"
  }
}
```

3. **实现 understanding.ts** — A1 自定义工具 + 拦截钩子
4. **实现 checkpoint.ts** — A2 `tool.execute.after` 钩子
5. **实现 verification.ts** — A3 自定义工具
6. **实现 audit.ts** — R5 审计钩子
7. **创建 `.quanttide/code/` 数据目录**

```
.quanttide/code/   ← gitignore
```

8. **启动 Opencode 验证**

重启 Opencode，Plugin 自动加载。发一条任务指令，检查是否触发理解披露拦截。

## Plugin API 参考

| 函数 | 签名 |
|------|------|
| Plugin 工厂 | `async (ctx: { project, client, $, directory, worktree }) => { hooks }` |
| 钩子 | `"event.name": async (input, output) => void` |
| 自定义工具 | `tool({ description, args: { key: tool.schema.type() }, execute })` |
| 阻断 | `throw new Error("message")` |

### input/output 结构

| 事件 | input | output |
|------|-------|--------|
| `tool.execute.before` | `{ tool: string, args: object }` | `{ args: object }`（可改） |
| `tool.execute.after` | `{ tool: string, args: object }` | `{ result: unknown }`（只读） |
| `experimental.session.compacting` | — | `{ context: string[], prompt?: string }` |
| `session.idle` | `{ event: { type: "session.idle" } }` | （只读） |
| `permission.asked` | `{ tool: string, args: object }` | （只读） |
| `permission.replied` | `{ tool: string, approved: boolean }` | （只读） |
