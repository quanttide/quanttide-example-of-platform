# 架构：System Two 编排层

## 分层

```
┌─────────────────────────────────────┐
│  think-agent (System Two)           │
│  意图管理 · 认知对齐 · 上下文编排     │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ IntentSyncBloc               │  │
│  │ aligned / ai_drift /         │  │
│  │ human_override               │  │
│  └──────────┬────────────────────┘  │
│             │ TUI API               │
└─────────────┼───────────────────────┘
              │
┌─────────────┼───────────────────────┐
│  OpenCode serve (System One)        │
│  AI 对话 · 代码生成 · 文件编辑       │
└─────────────────────────────────────┘
```

## TUI API 编排机制

| 接口 | 用途 |
|------|------|
| `POST /tui/append-prompt` | 隐式同步：追加系统消息到输入框 |
| `POST /tui/submit-prompt` | 提交隐式同步消息（不在对话渲染） |
| `POST /tui/clear-prompt` | 清理输入 |
| `POST /tui/execute-command` | 方向约束：执行自定义命令修正上下文 |
| `POST /tui/show-toast` | 通知用户"意图已同步"或"同步失败" |
| `POST /tui/open-sessions` | 自动初始化新会话 |

## 编排场景

### 隐式同步

人类编辑右栏意图文档后：

1. `IntentFileService` 检测文件变更
2. `IntentSyncBloc` 切到 `HumanOverride` 状态
3. 构造系统消息：`[SYSTEM] 意图文档已被用户手动更新...`
4. `POST /tui/append-prompt` 注入消息
5. `POST /tui/submit-prompt` 提交（不渲染到对话）
6. 收到 `sync_complete` 后切回 `Aligned`

### 方向约束

AI 上下文漂移时：

1. 检测对话方向与意图模型偏离
2. 通过 `append-prompt` 注入带有约束权重的修正指令
3. 调整 `AGENTS.md` 中系统提示的约束条目权重
4. 修正后继续正常对话

### 状态反馈

- 同步成功：`show-toast("意图已同步")`
- 同步失败：`show-toast("同步失败，将在下轮消息中附加文档", variant: "warning")`
- `HumanOverride` 阻塞超时：降级为在用户消息中显式携带意图文档

## 实现状态

`lib/blocs/intent_sync_bloc.dart:225` — `_sendToAi()` 当前为 TODO 占位，待接入 OpenCode serve 的 TUI API。
