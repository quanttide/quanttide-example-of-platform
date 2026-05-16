import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/intent_sync_bloc.dart';
import '../models/intent_model.dart';
import '../services/intent_file_service.dart';
import '../widgets/chat_panel.dart';
import '../widgets/intent_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  IntentModel _intentModel = IntentModel();
  IntentFileService? _fileService;

  @override
  void initState() {
    super.initState();
    _initFileService();
  }

  void _initFileService() {
    _fileService = IntentFileService(filePath: '.quanttide/intent.md');
    _fileService!.onFileChanged = (content) {
      context.read<IntentSyncBloc>().add(AiEditFile(content));
    };
    _fileService!.watch();
  }

  void _onIntentChanged(IntentModel model) {
    context.read<IntentSyncBloc>().add(HumanEditSave(model.toMarkdown()));
  }

  @override
  void dispose() {
    _fileService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    return BlocBuilder<IntentSyncBloc, IntentSyncState>(
      builder: (context, state) {
        _intentModel = IntentModel.fromMarkdown(state.documentContent);
        if (isWide) {
          return _buildDesktopLayout();
        }
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        const Expanded(child: ChatPanel()),
        Container(width: 1, color: Colors.grey[300]),
        Expanded(
          child: IntentPanel(
            intentModel: _intentModel,
            onChanged: _onIntentChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        ExpansionTile(
          title: const Text('当前意图'),
          initiallyExpanded: false,
          children: [
            SizedBox(
              height: 250,
              child: IntentPanel(
                intentModel: _intentModel,
                onChanged: _onIntentChanged,
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        const Expanded(child: ChatPanel()),
      ],
    );
  }
}
