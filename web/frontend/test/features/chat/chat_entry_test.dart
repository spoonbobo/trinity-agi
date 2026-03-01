import 'package:flutter_test/flutter_test.dart';
import 'package:trinity_shell/features/chat/chat_stream.dart';

void main() {
  group('ChatEntry', () {
    test('creates with required fields', () {
      final entry = ChatEntry(role: 'user', content: 'hello');
      expect(entry.role, 'user');
      expect(entry.content, 'hello');
      expect(entry.toolName, isNull);
      expect(entry.isStreaming, false);
      expect(entry.attachments, isNull);
      expect(entry.timestamp, isNotNull);
    });

    test('creates with all fields', () {
      final ts = DateTime(2026, 1, 1);
      final attachments = [
        {'name': 'photo.jpg', 'mimeType': 'image/jpeg', 'base64': 'abc'}
      ];
      final entry = ChatEntry(
        role: 'assistant',
        content: 'response',
        toolName: 'exec',
        isStreaming: true,
        attachments: attachments,
        timestamp: ts,
      );
      expect(entry.role, 'assistant');
      expect(entry.toolName, 'exec');
      expect(entry.isStreaming, true);
      expect(entry.attachments!.length, 1);
      expect(entry.timestamp, ts);
    });

    test('copyWith preserves non-overridden fields', () {
      final original = ChatEntry(
        role: 'tool',
        content: 'running...',
        toolName: 'exec',
        isStreaming: true,
        attachments: [{'name': 'test.txt'}],
      );
      final updated = original.copyWith(content: 'Done', isStreaming: false);
      expect(updated.role, 'tool');
      expect(updated.content, 'Done');
      expect(updated.isStreaming, false);
      expect(updated.toolName, 'exec');
      expect(updated.attachments!.length, 1);
    });

    test('copyWith with no overrides returns equivalent entry', () {
      final original = ChatEntry(role: 'system', content: 'info');
      final copy = original.copyWith();
      expect(copy.role, original.role);
      expect(copy.content, original.content);
      expect(copy.isStreaming, original.isStreaming);
    });
  });
}
