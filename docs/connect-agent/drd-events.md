基于我们刚刚确定的三张表和极简业务流程，提炼出以下关键命令与领域事件，它们共同构成了沟通系统的行为骨架。

—

核心命令（Commands）

命令 说明 目标实体
SendMessage 发送一条新消息（用户或AI） Message
EditMessage 修改某条消息的内容 Message
ProposeConsensus 从若干消息中提炼出一个共识（提议状态） Consensus + Relation
ConfirmConsensus 将提议中的共识标记为已确认 Consensus
DeprecateConsensus 将已确认的共识标记为废弃 Consensus
LinkMessageToConsensus 为消息和共识建立关联 Relation
UnlinkMessageFromConsensus 移除消息与共识的关联 Relation

（注：ProposeConsensus 通常会同时创建多条 Relation，可以设计为一个复合命令。）

—

核心领域事件（Domain Events）

事件名称统一为过去式，代表已经发生的事实。

事件 触发命令 关键数据
MessageSent SendMessage messageId, content, role, timestamp
MessageEdited EditMessage messageId, newContent, updatedAt
ConsensusProposed ProposeConsensus consensusId, content, proposedAt, relatedMessageIds[]
ConsensusConfirmed ConfirmConsensus consensusId, confirmedAt
ConsensusDeprecated DeprecateConsensus consensusId, deprecatedAt
MessageLinkedToConsensus LinkMessageToConsensus relationId, messageId, consensusId
MessageUnlinkedFromConsensus UnlinkMessageFromConsensus relationId, messageId, consensusId

—

状态流转与事件的对应关系

```
消息生命周期:
  [SendMessage] → MessageSent
  [EditMessage] → MessageEdited

共识生命周期:
  [ProposeConsensus] → ConsensusProposed (status = proposed)
        ↓
  [ConfirmConsensus] → ConsensusConfirmed (status = confirmed)
        ↓
  [DeprecateConsensus] → ConsensusDeprecated (status = deprecated)

关联关系:
  [LinkMessageToConsensus] → MessageLinkedToConsensus
  [UnlinkMessageFromConsensus] → MessageUnlinkedFromConsensus
```
