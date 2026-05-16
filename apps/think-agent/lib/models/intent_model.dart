class IntentModel {
  final String goal;
  final String exploration;
  final String constraints;
  final String state;
  final DateTime updatedAt;

  IntentModel({
    this.goal = '',
    this.exploration = '',
    this.constraints = '',
    this.state = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  IntentModel copyWith({
    String? goal,
    String? exploration,
    String? constraints,
    String? state,
    DateTime? updatedAt,
  }) {
    return IntentModel(
      goal: goal ?? this.goal,
      exploration: exploration ?? this.exploration,
      constraints: constraints ?? this.constraints,
      state: state ?? this.state,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  String toMarkdown() {
    return '''# 意图文档
生成时间：${updatedAt.toIso8601String()}

## 目标
$goal

## 当前探索
$exploration

## 约束
$constraints

## 状态
$state''';
  }

  String toContextString() {
    return '''当前意图模型：
## 目标
$goal
## 当前探索
$exploration
## 约束
$constraints
## 状态
$state''';
  }

  static IntentModel fromMarkdown(String markdown) {
    final goal = _extractSection(markdown, '## 目标');
    final exploration = _extractSection(markdown, '## 当前探索');
    final constraints = _extractSection(markdown, '## 约束');
    final state = _extractSection(markdown, '## 状态');
    return IntentModel(
      goal: goal,
      exploration: exploration,
      constraints: constraints,
      state: state,
    );
  }

  static String _extractSection(String markdown, String heading) {
    final start = markdown.indexOf(heading);
    if (start == -1) return '';
    final contentStart = markdown.indexOf('\n', start);
    if (contentStart == -1) return '';
    final headings = ['## 目标', '## 当前探索', '## 约束', '## 状态'];
    int end = markdown.length;
    for (final h in headings) {
      if (h == heading) continue;
      final idx = markdown.indexOf(h, contentStart);
      if (idx != -1 && idx < end) end = idx;
    }
    return markdown.substring(contentStart, end).trim();
  }
}
