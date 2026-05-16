import 'package:flutter_test/flutter_test.dart';
import 'package:think_agent/blocs/intent_sync_bloc.dart';
import 'package:think_agent/services/intent_file_service.dart';

void main() {
  test('IntentSyncBloc initial state is Aligned', () {
    final file = IntentFileService(filePath: '/tmp/test_intent.md');
    final bloc = IntentSyncBloc(
      initialDocumentContent: '# test',
      fileService: file,
    );
    expect(bloc.state, isA<Aligned>());
    bloc.close();
  });
}
