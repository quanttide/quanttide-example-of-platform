import 'dart:async';

abstract class DocumentStorage {
  Future<String> read();
  Future<void> write(String content);
  Stream<String> watch();
  Future<void> dispose();
}
