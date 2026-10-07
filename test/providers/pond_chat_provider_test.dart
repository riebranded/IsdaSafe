import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/chat_message.dart';
import 'package:isdasafev2/providers/pond_chat_provider.dart';
import 'package:isdasafev2/services/pond_chat_service.dart';

class _FakeChatService implements PondChatService {
  _FakeChatService({this.failures = 0});

  int failures;
  final calls = <List<ChatMessage>>[];

  @override
  Future<String> send({
    required List<ChatMessage> messages,
    required Map<String, Object?> context,
    required ChatTopic topic,
  }) async {
    calls.add(messages);
    if (failures > 0) {
      failures--;
      throw Exception('Busy');
    }
    return 'Reply ${calls.length}';
  }
}

void main() {
  Map<String, Object?> ctx() => {};

  test('send appends the user message and the reply', () async {
    final service = _FakeChatService();
    final chat = PondChatProvider(service: service);

    await chat.send('  How much to feed? ', topic: ChatTopic.feeding, context: ctx);

    expect(chat.messages.map((m) => m.text), ['How much to feed?', 'Reply 1']);
    expect(chat.messages.last.isUser, isFalse);
    expect(chat.error, isNull);
    expect(chat.sending, isFalse);
  });

  test('blank input is ignored', () async {
    final service = _FakeChatService();
    final chat = PondChatProvider(service: service);

    await chat.send('   ', topic: ChatTopic.general, context: ctx);

    expect(service.calls, isEmpty);
    expect(chat.messages, isEmpty);
  });

  test('failure keeps the question; retry re-asks without duplicating it', () async {
    final service = _FakeChatService(failures: 1);
    final chat = PondChatProvider(service: service);

    await chat.send('Is it safe?', topic: ChatTopic.risks, context: ctx);
    expect(chat.error, 'Busy');
    expect(chat.messages.length, 1);

    await chat.retry(topic: ChatTopic.risks, context: ctx);
    expect(chat.error, isNull);
    expect(chat.messages.map((m) => m.text), ['Is it safe?', 'Reply 2']);
  });

  test('clear empties the conversation', () async {
    final chat = PondChatProvider(service: _FakeChatService());
    await chat.send('Hi', topic: ChatTopic.general, context: ctx);

    chat.clear();

    expect(chat.messages, isEmpty);
  });

  test('forPond returns the same session per pond', () {
    PondChatProvider.resetSessions();
    expect(PondChatProvider.forPond('a'), same(PondChatProvider.forPond('a')));
    expect(PondChatProvider.forPond('a'), isNot(same(PondChatProvider.forPond('b'))));
  });
}
