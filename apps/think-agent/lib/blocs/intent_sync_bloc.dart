import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class IntentSyncState {
  final String documentContent;
  final String? lastApprovedContent;
  const IntentSyncState({
    required this.documentContent,
    this.lastApprovedContent,
  });
}

class Aligned extends IntentSyncState {
  const Aligned({required super.documentContent})
      : super(lastApprovedContent: documentContent);
}

class AiDrift extends IntentSyncState {
  const AiDrift({
    required super.documentContent,
    required super.lastApprovedContent,
  });
}

class HumanOverride extends IntentSyncState {
  const HumanOverride({
    required super.documentContent,
    required super.lastApprovedContent,
  });
}

sealed class IntentSyncEvent {
  const IntentSyncEvent();
}

class AiEditFile extends IntentSyncEvent {
  final String newContent;
  const AiEditFile(this.newContent);
}

class HumanEditSave extends IntentSyncEvent {
  final String newContent;
  const HumanEditSave(this.newContent);
}

class HumanReviewConfirm extends IntentSyncEvent {
  const HumanReviewConfirm();
}

class SyncComplete extends IntentSyncEvent {
  const SyncComplete();
}

class UserSendMessage extends IntentSyncEvent {
  final String? editedContent;
  const UserSendMessage({this.editedContent});
}

class IntentSyncBloc extends Bloc<IntentSyncEvent, IntentSyncState> {
  Completer<void>? _syncCompleter;
  bool _isSyncing = false;

  IntentSyncBloc({required String initialDocumentContent})
      : super(Aligned(documentContent: initialDocumentContent)) {
    on<AiEditFile>(_onAiEditFile);
    on<HumanEditSave>(_onHumanEditSave);
    on<HumanReviewConfirm>(_onHumanReviewConfirm);
    on<SyncComplete>(_onSyncComplete);
    on<UserSendMessage>(_onUserSendMessage);
  }

  void _onAiEditFile(AiEditFile event, Emitter<IntentSyncState> emit) {
    final newContent = event.newContent;
    switch (state) {
      case Aligned():
        emit(AiDrift(
          documentContent: newContent,
          lastApprovedContent: state.documentContent,
        ));
      case AiDrift():
        emit(AiDrift(
          documentContent: newContent,
          lastApprovedContent: state.lastApprovedContent,
        ));
      case HumanOverride():
        emit(HumanOverride(
          documentContent: newContent,
          lastApprovedContent: state.lastApprovedContent,
        ));
    }
  }

  void _onHumanEditSave(HumanEditSave event, Emitter<IntentSyncState> emit) {
    final previousApproved = switch (state) {
      Aligned() => state.documentContent,
      AiDrift(:final lastApprovedContent) => lastApprovedContent,
      HumanOverride(:final lastApprovedContent) => lastApprovedContent,
    };
    emit(HumanOverride(
      documentContent: event.newContent,
      lastApprovedContent: previousApproved,
    ));
    _startImplicitSync(event.newContent);
  }

  void _onHumanReviewConfirm(
      HumanReviewConfirm event, Emitter<IntentSyncState> emit) {
    if (state is AiDrift) {
      emit(Aligned(documentContent: state.documentContent));
    }
  }

  void _onSyncComplete(SyncComplete event, Emitter<IntentSyncState> emit) {
    if (state is HumanOverride) {
      emit(Aligned(documentContent: state.documentContent));
      _isSyncing = false;
      _syncCompleter?.complete();
      _syncCompleter = null;
    }
  }

  Future<void> _onUserSendMessage(
      UserSendMessage event, Emitter<IntentSyncState> emit) async {
    if (event.editedContent != null) {
      add(HumanEditSave(event.editedContent!));
      await _waitForSync();
      return;
    }
    if (state is AiDrift) {
      add(const HumanReviewConfirm());
      return;
    }
    if (state is HumanOverride) {
      await _waitForSync();
      return;
    }
  }

  void _startImplicitSync(String content) {
    if (_isSyncing) return;
    _isSyncing = true;
    final systemMessage = _buildSyncMessage(content);
    _sendToAi(systemMessage).then((_) {
      add(const SyncComplete());
    }).catchError((error) {
      _isSyncing = false;
      _syncCompleter?.completeError(error);
      _syncCompleter = null;
    });
  }

  String _buildSyncMessage(String content) {
    return '''
[SYSTEM] 意图文档已被用户手动更新，当前内容如下：
---
$content
---
请基于此意图文档继续对话。''';
  }

  Future<void> _sendToAi(String message) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<void> _waitForSync() async {
    if (_syncCompleter != null) return;
    _syncCompleter = Completer<void>();
    try {
      await _syncCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _isSyncing = false;
          _syncCompleter = null;
        },
      );
    } catch (_) {}
  }
}
