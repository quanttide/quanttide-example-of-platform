import 'package:flutter_test/flutter_test.dart';
import 'package:think_agent/blocs/intent_sync_bloc.dart';

void main() {
  test('IntentSyncBloc initial state is Aligned', () {
    final bloc = IntentSyncBloc(initialDocumentContent: '# test');
    expect(bloc.state, isA<Aligned>());
    bloc.close();
  });
}
