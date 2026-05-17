import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cubits/markdown_document_cubit.dart';

class MarkdownEditorPanel extends StatefulWidget {
  final MarkdownDocumentCubit cubit;
  final String filePath;
  const MarkdownEditorPanel({super.key, required this.cubit, required this.filePath});

  @override
  State<MarkdownEditorPanel> createState() => _MarkdownEditorPanelState();
}

class _MarkdownEditorPanelState extends State<MarkdownEditorPanel> {
  late TextEditingController _controller;
  StreamSubscription? _cubitSub;
  bool _isInternalChange = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.cubit.state);
    _cubitSub = widget.cubit.stream.listen((content) {
      if (_controller.text != content) {
        _isInternalChange = true;
        _controller.text = content;
      }
    });
  }

  @override
  void dispose() {
    _cubitSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    if (_isInternalChange) {
      _isInternalChange = false;
      return;
    }
    widget.cubit.fromEditor(text);
  }

  void _export() {
    Clipboard.setData(ClipboardData(text: _controller.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('文档已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filePath),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_copy),
            onPressed: _export,
            tooltip: '导出',
          ),
        ],
      ),
      body: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
          hintText: '在此输入 Markdown 内容...',
        ),
        style: const TextStyle(
          fontSize: 14,
          fontFamily: 'monospace',
          height: 1.6,
        ),
        onChanged: _onChanged,
      ),
    );
  }
}
