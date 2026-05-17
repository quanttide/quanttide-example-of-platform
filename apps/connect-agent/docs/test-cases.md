# connect-agent 测试用例说明

## 概述

本文档列出所有测试用例的意图、输入和验证点，作为 DRD 和代码实现之间的追溯依据。每个用例对应一个具体的业务规则或边界条件。

---

## 数据模型（test_models.py）

### Message

| 用例 | 验证 | 输入 | 断言 |
|------|------|------|------|
| `test_create` | 消息创建的基本字段 | content="你好", role=user | content=="你好", role==user, id 为 12 位字符串, created_at 为 datetime |
| `test_default_role` | role 不影响赋值 | content="test", role=agent | role==agent |
| `test_updated_at_none_by_default` | 新建消息无编辑时间 | content="test", role=system | updated_at is None |

### Consensus

| 用例 | 验证 | 输入 | 断言 |
|------|------|------|------|
| `test_create_proposed` | 新建共识默认为 proposed | content="测试共识" | status==proposed |
| `test_status_enum` | 可指定 confirmed | content="test", status=confirmed | status==confirmed |
| `test_deprecated` | 可指定 deprecated | content="test", status=deprecated | status==deprecated |

### Relation

| 用例 | 验证 | 输入 | 断言 |
|------|------|------|------|
| `test_create` | 关联创建 | message_id="msg1", consensus_id="con1" | message_id=="msg1", consensus_id=="con1" |
| `test_unique_id` | 每次创建 ID 不同 | 相同参数创建两次 | r1.id != r2.id |

---

## 存储层（test_storage.py）

### 消息操作

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_add_and_get_message` | 写入后能读出 | add → get | got.content=="hello" |
| `test_list_messages_empty` | 空库列表 | list_messages() | 返回 [] |
| `test_list_messages` | 多条消息 | add 两条 → list | len==2 |
| `test_update_message` | 修改内容 | add → update → get | content=="edited", updated_at not None |
| `test_update_message_not_found` | 修改不存在的 ID | update("nonexistent") | 返回 None |

### 共识操作

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_add_and_get_consensus` | 写入后能读出 | add → get | got.content=="共识" |
| `test_list_consensuses_by_status` | 按状态过滤 | 写入 proposed 和 confirmed 各一 | 过滤 proposed 返回 1 条，confirmed 返回 1 条 |
| `test_update_consensus_status` | 状态变更 | add proposed → update to confirmed | get.status==confirmed |
| `test_update_consensus_status_not_found` | 修改不存在的 ID | update("x") | 返回 None |

### 关联操作

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_relation_crud` | 增加和删除 | add → get → remove | remove 返回 True，再次 get 为空 |
| `test_relation_not_found` | 删除不存在的 ID | remove("nonexistent") | 返回 False |
| `test_get_relations_for_message` | 按消息查询关联 | 写入 3 条，m1 关联 2 条 | get("m1") 返回 2 条，get("m2") 返回 1 条 |

### 持久化与容错

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_persistence` | 数据落盘后能恢复 | add → 新建 Storage 同路径读回 | 数据一致 |
| `test_empty_file_handling` | 空文件不崩溃 | 写入 "" → 新建 Storage | list_messages() 返回 [] |
| `test_corrupted_file_returns_empty` | 损坏的 JSON 不崩溃 | 写入 "{invalid" → 新建 Storage | list_messages() 返回 []，list_consensuses() 返回 [] |

---

## 命令层（test_commands.py）

### 事件总线

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_publish_with_protocol_handler` | EventHandler 协议对象被调用 | register(handler with .handle()) → publish | handler.events 长度为 1 |
| `test_publish_with_callable` | 普通函数被调用 | register(普通函数) → publish | received 长度为 1 |
| `test_publish_multiple_handlers` | 多个 handler 都收到 | register 3 个 handler → publish | 每个 handler 都收到 1 次 |

### 消息命令

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_send_message` | 发送消息并发布事件 | send_message("你好", user) | content=="你好", role==user, 事件列表含 message_id |
| `test_edit_message` | 编辑消息 | send → edit(id, "edited") | updated.content=="edited" |
| `test_edit_message_not_found` | 编辑不存在的消息 | edit("nonexistent") | 返回 None |

### 共识命令

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_propose_consensus` | 提议共识并建立关联 | send → propose(content, [msg.id]) | status=="proposed", relation 指向该消息 |
| `test_propose_with_invalid_message` | 无效消息 ID 不创建关联 | propose(content, ["nonexistent"]) | 无 relation 创建 |
| `test_confirm_consensus` | 确认共识 | propose → confirm(id) | status=="confirmed" |
| `test_confirm_not_found` | 确认不存在的共识 | confirm("nonexistent") | 返回 None |
| `test_deprecate_consensus` | 废弃共识 | propose → confirm → deprecate(id) | status=="deprecated" |

### 关联命令

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_link_message_to_consensus` | 建立关联 | send → propose → link(msg.id, con.id) | r.message_id==msg.id |
| `test_link_invalid_message` | 关联不存在的消息 | link("bad", con.id) | 返回 None |
| `test_link_invalid_consensus` | 关联不存在的共识 | link(msg.id, "bad") | 返回 None |
| `test_unlink_message_from_consensus` | 解除关联 | propose 含 msg → unlink(relation.id) | 返回 True |
| `test_unlink_not_found` | 解除不存在的关联 | unlink("nonexistent") | 返回 False |

### 完整生命周期

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_full_lifecycle` | Message → Consensus 全流程 | send → propose → confirm → deprecate | status 依次为 proposed → confirmed → deprecated |

---

## 智能体（test_agents.py）

### 消息智能体（System 1）

| 用例 | 验证 | 输入 | 断言 |
|------|------|------|------|
| `test_consensus_summary_empty` | 无共识时的摘要文案 | get_consensus_summary([]) | 返回含"暂无已确认的共识" |
| `test_consensus_summary_with_items` | 有共识时列出内容 | summary([{content:"PostgreSQL"}, {content:"Python"}]) | 字符串含两项内容 |
| `test_reply_sends_correct_prompt` | system prompt 注入共识 + 回复正确返回 | mock LLM 返回"好的，就用 PostgreSQL" | prompt 含"用 PostgreSQL"，reply 为 mock 返回值 |
| `test_reply_without_history` | 无历史记录也能回复 | mock LLM + 空 history | reply 为 mock 返回值 |

### 共识智能体（System 2）— 指令解析

| 用例 | 验证 | 输入 | 断言 |
|------|------|------|------|
| `test_parse_action_full` | 完整指令块解析 | propose 含 action/content/related_messages | 返回 dict 包含三个字段 |
| `test_parse_action_minimal` | 仅含 action + content | confirm 无 related_messages | action=="confirm" |
| `test_parse_action_missing_action` | 缺 action 字段 | content 无 action | 返回 None |
| `test_parse_action_related_messages_json` | JSON 数组格式 | related_messages: `["a","b"]` | 返回 ["a", "b"] |
| `test_parse_action_related_messages_quoted` | 引号分隔格式（fallback） | `"x" "y"` 非 JSON | "x" 在结果中 |

### 共识智能体（System 2）— 指令执行

| 用例 | 验证 | 步骤 | 断言 |
|------|------|------|------|
| `test_execute_propose` | propose 指令创建共识和关联 | send → execute(propose, content, [msg.id]) | consensus 被创建，relation 指向 msg |
| `test_execute_confirm` | confirm 匹配并确认 | propose → execute(confirm, 相同 content) | status==confirmed |
| `test_execute_confirm_no_match` | confirm 不匹配时不改变 | propose → execute(confirm, 不同 content) | status 仍为 proposed |
| `test_execute_deprecate` | deprecate 匹配并废弃 | propose → confirm → execute(deprecate, 相同 content) | status==deprecated |
| `test_execute_deprecate_no_match` | deprecate 不匹配时不改变 | propose → confirm → execute(deprecate, 不同 content) | status 仍为 confirmed |

### 共识智能体（System 2）— 观察流程

| 用例 | 验证 | mock 返回 | 断言 |
|------|------|-----------|------|
| `test_observe_propose` | LLM 返回 propose → 共识被创建 | `[CONSENSUS_ACTION]action: propose...` | storage 含 proposed 共识 |
| `test_observe_no_action` | LLM 返回 [NO_ACTION] → 无变化 | `[NO_ACTION]` | 无共识创建 |
| `test_observe_with_proposed_context` | 已有 proposed 共识时上下文包含它 | `[NO_ACTION]`（验证上下文字符串） | 发送给 LLM 的 prompt 含"待确认的共识" |
| `test_observe_with_confirmed_context` | 已有 confirmed 共识时上下文包含它 | `[NO_ACTION]`（验证上下文字符串） | 发送给 LLM 的 prompt 含"已确认的共识" |

---

## 入口 REPL（test_main.py）

| 用例 | 验证 | 输入序列 | 断言 |
|------|------|---------|------|
| `test_default_data_path` | 默认 data 路径 | argparse 默认值 | args.data=="data.json" |
| `test_custom_data_path` | 自定义 data 路径 | `--data custom.json` | args.data=="custom.json" |
| `test_module_importable` | 模块可导入 | `import app.main` | callable(main) |
| `test_quit_via_eof` | Ctrl+D 退出 | EOFError | print("\\n再见。") |
| `test_quit_command` | /quit 退出 | "/quit" | print("再见。") |
| `test_exit_command` | /exit 退出 | "/exit" | print("再见。") |
| `test_unknown_command` | 未知命令提示 | "/unknown" → "/quit" | print("未知命令: /unknown") |
| `test_help_command` | 帮助信息 | "/help" → "/quit" | 输出含 "/quit" 和 "/help" |
| `test_empty_input_skipped` | 空输入跳过 | "" → "/quit" | 不报错，正常退出 |
| `test_messages_command` | 消息列表 | "/messages" → "/quit" | 输出含消息内容 |
| `test_messages_with_content` | 消息内容显示 | "/messages" → "/quit" | 输出含测试消息内容 |
| `test_consensuses_command` | 共识列表 | "/consensuses" → "/quit" | 输出含共识内容 |
| `test_consensuses_with_relations` | 共识含有关联时显示 | mock 返回含 relation → "/consensuses" → "/quit" | 输出含 msg ID |
| `test_confirm_command` | 确认共识 | "/confirm abc123" → "/quit" | update_consensus_status 被调用 |
| `test_confirm_not_found` | 找不到共识提示 | storage 返回 None → "/confirm xxx" → "/quit" | print("未找到该共识") |
| `test_deprecate_command` | 废弃共识成功提示 | storage 返回 Consensus → "/deprecate abc123" → "/quit" | 输出含"已废弃" |
| `test_deprecate_not_found` | 找不到共识提示 | storage 返回 None → "/deprecate xxx" → "/quit" | print("未找到该共识") |
| `test_history_command` | 历史消息 | 先发一条消息 → "/history" → "/quit" | 输出含用户消息和 AI 回复 |
| `test_normal_conversation` | 完整对话流程 | "你好" → "/quit" | msg_agent.reply 和 con_agent.observe 被调用 |

---

## 集成测试（integration_tests/test_lifecycle.py）

| 用例 | 对应 DRD | 步骤 | 断言 |
|------|---------|------|------|
| `test_user_says_write_it_down` | 从消息中提炼共识 | 用户说"记下来，我们用 PostgreSQL" → System 1 回复 → System 2 观察 | 至少一条 proposed 共识，内容含 PostgreSQL |
| `test_small_talk_no_consensus` | 无关对话不产生共识 | 用户说"今天天气不错" → System 1 回复 → System 2 观察 | 无共识生成 |
| `test_user_confirms_and_deprecates` | 共识状态流转 | ① 提出 PostgreSQL → ② 手动 confirm → ③ 反悔改为 MySQL → System 2 观察 | 第一步产生 proposed，第二步变为 confirmed，第三步原有共识被废弃或有新 proposed |
| `test_reply_references_consensus` | AI 回复呼应已有共识 | ① 预设 confirmed 共识"PostgreSQL" → ② 用户问"用什么数据库" → System 1 回复 | 回复内容含 PostgreSQL |

---

## 追溯关系

```
DRD 业务规则
  ├── 消息被记录 → test_models.Message.* + test_storage.消息操作
  ├── 共识被提炼 → test_commands.共识命令 + test_agents.指令执行
  ├── 状态流转   → test_commands.test_full_lifecycle
  ├── 关联溯源   → test_storage.关联操作 + test_commands.关联命令
  ├── 用户确认   → test_main.REPL 命令
  └── 自然结晶   → test_agents.观察流程 + integration_tests.*
```
