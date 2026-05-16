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

  static const _darkCard = Color(0xFF16213E);
  static const _darkText = Color(0xFFE8E8E8);
  static const _darkLabel = Color(0xFF8E8E9A);
  static const _accent = Color(0xFF4FC3F7);

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
      SnackBar(
        content: const Text('BRD 已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _darkCard,
      ),
    );
  }

  Widget _buildField(String label, IconData icon, String key,
      {int maxLines = 4}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              children: [
                Icon(icon, size: 13, color: _accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _darkLabel,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _darkCard,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _controllers[key]!,
              maxLines: maxLines,
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                hintText: label,
                hintStyle: TextStyle(color: _darkLabel.withAlpha(100)),
              ),
              style: const TextStyle(
                fontSize: 13,
                color: _darkText,
                height: 1.5,
              ),
              onChanged: (_) => _onFieldChanged(key),
            ),
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
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '意图模型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _darkText,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(_model.updatedAt),
                style: TextStyle(fontSize: 11, color: _darkLabel),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Divider(color: _darkLabel.withAlpha(40), height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              _buildField('目标', Icons.flag_outlined, 'goal'),
              _buildField('当前探索', Icons.explore_outlined, 'exploration',
                  maxLines: 6),
              _buildField('约束', Icons.border_style, 'constraints',
                  maxLines: 4),
              _buildField('状态', Icons.circle_outlined, 'state'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportBrd,
              icon: const Icon(Icons.file_copy, size: 15),
              label: const Text('导出 BRD'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withAlpha(80)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
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
