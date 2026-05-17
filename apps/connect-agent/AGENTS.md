# AGENTS.md - connect-agent

## 设计概要

人机沟通共识引擎。核心模型：

- **消息智能体 (System 1)** — 快思考，与人类自然对话
- **共识智能体 (System 2)** — 慢思考，异步提炼共识

### 数据模型

| 实体 | 职责 |
|------|------|
| Message | 对话原始内容 |
| Consensus | 提炼出的共识（proposed → confirmed → deprecated） |
| Relation | 消息与共识的多对多关联 |

### 文档索引

| 文档 | 用途 |
|------|------|
| `docs/connect-agent/default.md` | 设计背景与思路 |
| `docs/connect-agent/add.md` | 双智能体架构设计 |
| `docs/connect-agent/drd-models.md` | 数据需求文档 - 模型 |
| `docs/connect-agent/drd-events.md` | 数据需求文档 - 命令与事件 |

## 工作纪律

- 保持极简，不做预测性设计
- 消息与共识分离，不阻塞对话
