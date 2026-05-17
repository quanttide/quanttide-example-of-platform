import 'package:flutter/material.dart';

class DocumentAgentLayout extends StatelessWidget {
  final Widget editor;
  final Widget chat;

  const DocumentAgentLayout({
    super.key,
    required this.editor,
    required this.chat,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    if (isWide) {
      return Row(
        children: [
          Expanded(flex: 3, child: editor),
          const VerticalDivider(width: 1),
          Expanded(flex: 2, child: chat),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: editor,
        ),
        const Divider(height: 1),
        Expanded(
          flex: 2,
          child: chat,
        ),
      ],
    );
  }
}
