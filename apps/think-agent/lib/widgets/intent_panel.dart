import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/intent_model.dart';

class IntentPanel extends StatefulWidget {
  final IntentModel intentModel;
  final ValueChanged<IntentModel> onChanged;
  const IntentPanel({
    super.key,
    required this.intentModel,
    required this.onChanged,
  });

  @override
  State<IntentPanel> createState() => _IntentPanelState();
}

class _IntentPanelState extends State<IntentPanel> {
  late IntentModel _model;
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _model = widget.intentModel;
    _initControllers();
  }

  @override
  void didUpdateWidget(IntentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intentModel != widget.intentModel) {
      _model = widget.intentModel;
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _controllers = {
      'goal': TextEditingController(text: _model.goal),
      'exploration': TextEditingController(text: _model.exploration),
      'constraints': TextEditingController(text: _model.constraints),
      'state': TextEditingController(text: _model.state),
    };
  }

  void _disposeControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _onFieldChanged(String field) {
    final updated = _model.copyWith(
      goal: _controllers['goal']!.text,
      exploration: _controllers['exploration']!.text,
      constraints: _controllers['constraints']!.text,
      state: _controllers['state']!.text,
    );
    setState(() => _model = updated);
    widget.onChanged(updated);
  }

  void _exportBrd() {
    final brd = _model.toMarkdown();
    Clipboard.setData(ClipboardData(text: brd));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('BRD 已复制到剪贴板')),
    );
  }

  Widget _buildField(String label, String key, {int maxLines = 4}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _controllers[key]!,
            maxLines: maxLines,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (_) => _onFieldChanged(key),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              const Text(
                '意图模型',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '最后更新: ${_formatTime(_model.updatedAt)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildField('目标', 'goal'),
              _buildField('当前探索', 'exploration', maxLines: 6),
              _buildField('约束', 'constraints', maxLines: 4),
              _buildField('状态', 'state'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportBrd,
              icon: const Icon(Icons.file_copy, size: 16),
              label: const Text('导出 BRD'),
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    return '${diff.inHours}小时前';
  }
}
