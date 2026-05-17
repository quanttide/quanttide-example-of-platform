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

这个接口不是为了让代码更好看，而是解决三个实际的功能问题。

—

1. 让状态机可独立验证

现在 IntentSyncBloc 的构造函数里直接依赖 OpenCodeService。这意味着：你要测试状态机的转换逻辑，必须先启动一个 Open Code 服务端。

加上接口后：

```dart
// 测试时用假实现，不碰真实服务端
class FakeDelegate implements IntentSyncDelegate {
  String fileContent = ’‘;
  String? lastSyncMessage;

  @override
  Future<void> writeIntentFile(String content) async => fileContent = content;

  @override
  Future<void> sendImplicitSync(String message) async => lastSyncMessage = message;
}

// 测试状态机转换，毫秒级完成
test(’ai_drift 下发送消息应被动确认‘, () async {
  final bloc = IntentSyncBloc(
    initialDocumentContent: initialDoc,
    delegate: FakeDelegate(),
  );
  bloc.add(AiEditFile(aiModifiedDoc));
  await bloc.add(UserSendMessage());
  expect(bloc.state, isA<Aligned>());
});
```

没接口时这22个测试用例跑一遍要等着 Open Code 启动和响应。有接口后纯逻辑验证，毫秒级完成。

—

2. 换底座时不改骨架

Open Code 是你现在复用的底座。但如果以后换成了别的服务端——比如你自己写的后端、或者另一个开源项目——骨架不用动。只需要重新实现 IntentSyncDelegate 的三个方法。

骨架逻辑（什么时候该同步、什么时候该阻塞、版本怎么对齐）是你花了整个对话推敲出来的，它不应该和 Open Code 的 API 格式绑定在一起。

—

3. 隐式同步的实现方式可以随时换

现在隐式同步是通过 appendPrompt + submitPrompt 实现的。但这两个接口的行为你可能还没完全摸清。如果实际使用时发现这种同步方式有问题——比如它会打断当前的对话流、或者会在 TUI 里留下痕迹——你可以换一种实现：

```dart
class DirectApiSyncDelegate implements IntentSyncDelegate {
  // 直接通过 session API 注入系统消息，绕过 TUI
  @override
  Future<void> sendImplicitSync(String message) async {
    await http.post(
      Uri.parse(’$baseUrl/session/$sessionId/system-message‘),
      body: jsonEncode({’text‘: message}),
    );
  }
}
```

骨架不关心你是怎么同步的，只关心你有没有完成同步。

—

一句话

接口的意义是让骨架逻辑独立于底座细节。独立意味着可以快速验证、可以自由替换、可以在不破坏核心逻辑的前提下试探底座能力。
