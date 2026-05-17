以下是对 IntentCubit 的业务建模说明，聚焦于它作为“意图文档”这一核心领域对象的唯一状态管理器。

—

IntentCubit 的业务建模

1. 领域定位

IntentCubit 代表了 当前对话中人类与 AI 共同维护的结构化意图文档。它不是简单的字符串容器，而是整个协同工作流中唯一的“意图状态”权威源（Source of Truth）。

2. 状态定义

状态类型：String —— 完整的 Markdown 文档。

之所以用普通字符串而非领域对象（如 IntentModel），是为了最大化灵活性：

· 外部编辑器可直接修改 .md 文件，无需解析为对象再序列化。
· AI 输出本身就是 Markdown，可原样替换。
· 用户通过文本编辑器自由编辑，不受字段限制。

3. 更新来源与业务规则

文档内容通过三种明确的操作进行修改，每种操作对应一个方法，体现了 “写入必须经过统一入口” 的约束。

方法 触发场景 业务规则
updateFromFile(content) 外部程序（如 IDE、文本编辑器）修改了文件 仅更新内存状态，不写回文件（避免自我循环），并忽略与当前内容相同的更新
updateFromEditor(content) 用户在意图编辑器中手动输入 更新内存状态，并立即写入文件（保持磁盘同步）
updateFromAi(content) AI 回复中包含 [INTENT_UPDATE] 块 更新内存状态，并写入文件（使 AI 的变更持久化，用户也可以看到）

防抖与去重：所有方法在修改前都执行 if (content != state) 判断，防止无意义的重建和文件写入。

4. 与外部依赖的协作

IntentCubit 持有 IntentFileService 的引用，负责将“手动编辑”和“AI 更新”两种变更持久化。它对外部完全透明：

· 给 ChatCubit：允许读取 state（用于作为系统提示发送），并调用 updateFromAi 将 AI 的更新注入。
· 给 UI：通过 BlocBuilder 暴露状态，并通过 updateFromEditor 接收编辑器的变更。

这种注入关系是单向依赖：IntentCubit 不依赖任何其他 Cubit，从而保持独立和可测试。

5. 行为约束

· 单线程非并发：Cubit 本身保证状态流转是同步的，多个更新请求会按调用顺序处理（BLoC 的事件队列机制）。
· 不解析内容：IntentCubit 将文档视为不透明字符串，不关心内部结构，保证了极简性和鲁棒性。
· 文件防抖：文件监听由 IntentFileService 内部实现 300ms 防抖，updateFromFile 仅接收最终结果，避免高频写入。

6. 生命周期

· 由 BlocProvider 在应用根节点创建，与 MaterialApp 同生命周期。
· 初始化时接收默认空模板（_defaultIntentDoc），随后由文件服务异步读取实际内容，通过 onFileChanged 回调触发 updateFromFile 覆盖。

—

总结：IntentCubit 将人机协同中“围绕文档的冲突写入”问题，转化为三个清晰的更新入口，所有修改都必须经过它，从而保证了状态的一致性和可追溯性。这是该架构中保证数据完整性的最关键一环。