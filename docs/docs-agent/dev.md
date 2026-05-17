以下是为“文档智能体”设计的通用方案。它在之前的三来源协同模式上，封装成可复用的 Flutter 包，并为未来扩展自主感知留出空间。

—

文档智能体（Document Agent）设计

1. 定位

一个以 Markdown 文档为中心的人机协同编辑组件，提供：

· 核心状态管理：一份文档，三个更新来源（文件/用户/AI），自动持久化和外部同步。
· 即插即用的 AI 对话：通过抽象服务接口连接任何后端 AI（OpenCode、OpenAI 等），在聊天中自动附带文档上下文，解析 AI 的结构化更新建议。
· 内置 UI：编辑器 + 聊天面板，可自由组合或独立使用。
· 主动智能体能力（可选）：可扩展为自主观察文档变化并主动提议修改的循环智能体。

—

2. 核心抽象

2.1 文档 Cubit（MarkdownDocumentCubit）

```dart
class MarkdownDocumentCubit extends Cubit<String> {
  final DocumentStorage _storage;

  MarkdownDocumentCubit({
    required String initialContent,
    required DocumentStorage storage,
  }) : _storage = storage,
       super(initialContent);

  void fromFile(String content) { ... }
  void fromEditor(String content) { ... }
  void fromAgent(String content) { ... }
}
```

2.2 存储接口（DocumentStorage）

```dart
abstract class DocumentStorage {
  Future<String> read();
  Future<void> write(String content);
  Stream<String> watch();
  Future<void> dispose();
}
```

内置实现：FileDocumentStorage，基于磁盘文件 + 防抖监听。

2.3 AI 对话服务（AiChatService）

```dart
abstract class AiChatService {
  Future<String?> createSession({String? title});
  Future<String?> sendMessage(
    String sessionId,
    String message, {
    String? systemPrompt,
  });
  Future<bool> clearSession(String sessionId);
}
```

内置实现：OpenCodeChatService，封装原有 HTTP 调用。

2.4 聊天 Cubit（ChatCubit）

```dart
class ChatCubit extends Cubit<ChatState> {
  final AiChatService _aiService;
  final MarkdownDocumentCubit _docCubit;

  Future<void> sendMessage(String text) async {
    // 1. 加入用户消息
    // 2. 读取 _docCubit.state 作为系统提示
    // 3. 调用 _aiService.sendMessage
    // 4. 解析回复中的 [INTENT_UPDATE] 并调用 _docCubit.fromAgent
    // 5. 更新消息列表
  }
}
```

—

3. UI 组件

3.1 MarkdownEditorPanel

· 全屏 Markdown 编辑器，绑定 docCubit.state
· onChanged → docCubit.fromEditor()
· 支持深色/浅色主题，可自定义样式
· 可选导出、撤销/重做（扩展后）

3.2 CollaborativeChatPanel

· 依赖 chatCubit 和 aiService
· 消息气泡列表，发送按钮
· 自动显示会话创建状态、AI 思考状态
· 可独立使用，无需文档 Cubit（但提供 systemPrompt 是可选的）

3.3 DocumentAgentLayout（可选）

一个组合布局，自动处理宽屏/窄屏切换：

```dart
class DocumentAgentLayout extends StatelessWidget {
  final Widget editor;
  final Widget chat;
  // 自行判断宽度，左右分栏或折叠
}
```

—

4. 智能体扩展点（主动感知）

当前设计是被动响应（用户发消息 → AI 回复 → 可能更新文档）。在此基础上可扩展为主动智能体，增加一个 AgentBrain 层：

```dart
class DocumentAgent {
  final MarkdownDocumentCubit docCubit;
  final AiChatService aiService;
  final String sessionId;
  Timer? _observationTimer;

  void startObservation(Duration interval) {
    _observationTimer = Timer.periodic(interval, (_) async {
      final currentDoc = docCubit.state;
      // 调用 AI 分析文档，判断是否需要主动建议
      final suggestion = await aiService.analyzeAndSuggest(sessionId, currentDoc);
      if (suggestion != null) {
        docCubit.fromAgent(suggestion);
      }
    });
  }
}
```

但此部分可以按需实现，不影响基本组件功能。

—

5. 包结构建议

```
markdown_agent/
├── lib/
│   ├── cubits/
│   │   ├── markdown_document_cubit.dart
│   │   └── chat_cubit.dart
│   ├── services/
│   │   ├── document_storage.dart       // 接口
│   │   ├── file_document_storage.dart  // 磁盘实现
│   │   ├── ai_chat_service.dart        // 接口
│   │   └── opencode_chat_service.dart  // OpenCode 实现
│   ├── ui/
│   │   ├── markdown_editor_panel.dart
│   │   ├── collaborative_chat_panel.dart
│   │   └── document_agent_layout.dart
│   └── markdown_agent.dart             // 入口，导出所有公共类
└── pubspec.yaml
```

—

6. 使用示例

```dart
void main() {
  final storage = FileDocumentStorage(’workspace/notes.md‘);
  final docCubit = MarkdownDocumentCubit(
    initialContent: ’# 项目文档\n...‘,
    storage: storage,
  );
  final aiService = OpenCodeChatService(host: ’127.0.0.1‘, port: 4096);
  final chatCubit = ChatCubit(aiService: aiService, docCubit: docCubit);

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: docCubit),
        BlocProvider.value(value: chatCubit),
      ],
      child: MaterialApp(
        home: DocumentAgentLayout(
          editor: MarkdownEditorPanel(cubit: docCubit),
          chat: CollaborativeChatPanel(cubit: chatCubit),
        ),
      ),
    ),
  );
}
```

—

7. 设计优势

· 职责分明：文档、对话、存储、AI 服务完全解耦，各司其职。
· 高度可替换：存储可从文件换成数据库，AI 可从 OpenCode 换成 ChatGPT API，UI 可自定义主题。
· 核心模式保留：三来源更新（fromFile, fromEditor, fromAgent）确保多源写入安全。
· 开箱即用：内置默认实现，零配置即可搭建人机协同编辑器。
· 渐进式复杂：可从被动对话升级为主动智能体，不破坏现有架构。

这个设计直接诞生于你之前探索的代码，现在它可以作为一个独立、通用的 Flutter 组件库，服务于任何需要“人 + AI 维护一份 Markdown 文档”的场景。
