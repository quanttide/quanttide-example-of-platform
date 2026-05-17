沟通系统数据需求文档（最终精简版）

1. 概述

本系统聚焦于人机协同沟通的核心：记录对话过程，并从中提炼可管理的共识。数据模型仅保留最必要的三个实体：消息、共识及其关联。

—

2. 核心实体

实体 职责
Message 记录对话原始内容，按时间排序
Consensus 记录从消息中提炼出的确定性结论
Relation 记录消息与共识之间的多对多关联

—

3. 数据表定义

3.1 消息表 (messages)

字段 类型 说明
id string 唯一标识
content string 消息文本内容
role string 发送者：user / agent / system
created_at datetime 首次发送时间
updated_at datetime 最后修改时间

· 允许编辑消息，created_at 保持不变。
· updated_at 等于 created_at 时表示未编辑。

3.2 共识表 (consensus)

字段 类型 说明
id string 唯一标识
content string 共识内容（Markdown）
status string 状态：proposed / confirmed / deprecated
created_at datetime 首次创建时间
updated_at datetime 最后更新时间

· 状态流转：提议 → 确认；不再适用时标记为废弃。

3.3 关联关系表 (relations)

字段 类型 说明
id string 唯一标识
message_id string 关联的消息 ID
consensus_id string 关联的共识 ID

· 纯多对多关联，只表示消息与共识之间存在溯源关系，不附加类型标签。

—

4. 生命周期

· 消息：创建后允许修改，updated_at 标记最后编辑时间。
· 共识：提议 → 确认（活跃），可标记为废弃。
· 关系：随共识的提取过程创建，可增删。

—

5. 典型业务流程

1. 对话产生消息。
2. 从消息中提炼共识，状态设为 proposed，并创建若干 relations 记录关联源消息。
3. 确认共识，状态改为 confirmed，可补充关联新的消息。
4. 废弃共识，状态改为 deprecated，移除或保留关联。

—

6. 设计原则

· 极致精简：三个实体，每个实体只保留核心字段（id + content + 必要时间字段），关系表无类型。
· 可立即实现：可直接映射为 SQLite 表或 JSON 文件。
· 只解决当前明确问题：记录对话与共识，建立溯源关联，不做任何预测性设计。
