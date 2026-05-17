我们需要让 IntentSyncBloc 成为纯骨架，不依赖 OpenCodeService 和 IntentFileService。它需要的平台能力只有两个：写入文件 和 发送隐式同步消息。把这俩抽象成一个接口即可。

—

IntentSyncDelegate 接口设计

```dart
/// 平台需实现的委托，供 IntentSyncBloc 调用。
/// 所有方法都是平台相关的副作用，骨架层不关心具体实现。
abstract class IntentSyncDelegate {
  /// 将意图文档写入文件（同步或异步均可）。
  /// 骨架在以下时机调用：
  /// - AI 编辑文件时（[AiEditFile]）
  /// - 人类手动编辑保存时（[HumanEditSave]）
  Future<void> writeIntentFile(String content);

  /// 向 AI 发送隐式同步消息（不在 UI 中渲染）。
  /// 骨架在人类编辑后调用，确保 AI 感知最新文档。
  /// 实现应保证消息注入 AI 上下文，不影响用户可见对话。
  Future<void> sendImplicitSync(String systemMessage);

  /// 可选：读取当前意图文件内容。
  /// 骨架在初始化或需要对比版本时可能使用。
  /// 若平台无法提供，可抛出 UnimplementedError，骨架会使用内部缓存。
  Future<String> readIntentFile() async {
    throw UnimplementedError(’readIntentFile not implemented‘);
  }
}
```

—

改造后的 IntentSyncBloc 构造函数

```dart
class IntentSyncBloc extends Bloc<IntentSyncEvent, IntentSyncState> {
  final IntentSyncDelegate _delegate;

  IntentSyncBloc({
    required String initialDocumentContent,
    required IntentSyncDelegate delegate,
  })  : _delegate = delegate,
        super(Aligned(documentContent: initialDocumentContent));
  // ...
}
```

内部调用处变更：

· 原来 _file.writeContent(...) → _delegate.writeIntentFile(...)
· 原来 _sendToAi(...) → 仍保留为私有方法，但其中 appendPrompt/submitPrompt 替换为 _delegate.sendImplicitSync(...)（或者直接把系统消息传给 sendImplicitSync，让实现决定怎么发送）
· _buildSyncMessage 保留，构造消息后传给 _delegate.sendImplicitSync

—

平台实现示例

```dart
class OpenCodeIntentSyncDelegate implements IntentSyncDelegate {
  final IntentFileService fileService;
  final OpenCodeService ocService;

  OpenCodeIntentSyncDelegate({
    required this.fileService,
    required this.ocService,
  });

  @override
  Future<void> writeIntentFile(String content) =>
      fileService.writeContent(content);

  @override
  Future<void> sendImplicitSync(String systemMessage) async {
    final appended = await ocService.appendPrompt(systemMessage);
    if (!appended) throw Exception(’隐式同步失败：无法追加 prompt‘);
    final submitted = await ocService.submitPrompt();
    if (!submitted) throw Exception(’隐式同步失败：无法提交 prompt‘);
  }

  @override
  Future<String> readIntentFile() => fileService.readContent();
}
```

—

职责边界

层 职责
IntentSyncBloc（库） 状态机逻辑、状态转换、决定何时调用 delegate
IntentSyncDelegate（接口） 定义平台需提供的能力（文件读写 + 隐式消息发送）
OpenCodeIntentSyncDelegate（平台） 使用 OpenCode 服务端和文件系统实现接口

这样骨架零依赖平台细节，可独立测试，且换一个服务端实现只需重新实现 IntentSyncDelegate。