import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/language_provider.dart';
import '../models/chat_message.dart';

/// Sends a conversation to the pond assistant and returns its reply. Factored
/// out so [PondChatProvider] can be unit tested against a fake.
abstract class PondChatService {
  Future<String> send({
    required List<ChatMessage> messages,
    required Map<String, Object?> context,
    required ChatTopic topic,
  });
}

/// Calls the `pond-chat` Supabase Edge Function (Gemini-backed), which needs
/// the signed-in user's session.
class SupabasePondChatService implements PondChatService {
  SupabasePondChatService({this._client});

  final SupabaseClient? _client;

  @override
  Future<String> send({
    required List<ChatMessage> messages,
    required Map<String, Object?> context,
    required ChatTopic topic,
  }) async {
    try {
      final response = await (_client ?? Supabase.instance.client).functions
          .invoke(
            'pond-chat',
            body: {
              'messages': [for (final m in messages) m.toJson()],
              'context': context,
              'topic': topic.wireName,
              'language': LanguageProvider.current.code,
            },
          );
      final data = response.data;
      final reply = data is Map ? data['reply'] : null;
      if (reply is! String || reply.trim().isEmpty) {
        throw Exception('The assistant sent an empty reply.');
      }
      return reply.trim();
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw Exception(
        message ?? "Couldn't reach the assistant. Please try again.",
      );
    }
  }
}
