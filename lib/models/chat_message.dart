import 'package:flutter/material.dart';
import '../l10n/tr.dart';

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  final ChatRole role;
  final String text;

  bool get isUser => role == ChatRole.user;

  Map<String, String> toJson() => {'role': role.name, 'text': text};
}

/// Which pond-dashboard section the chat was opened from. Shapes the greeting,
/// the suggested questions, and the hint sent to the model.
enum ChatTopic { general, feeding, waterQuality, risks }

extension ChatTopicInfo on ChatTopic {
  /// Sent to the `pond-chat` function.
  String get wireName => switch (this) {
    ChatTopic.general => 'general',
    ChatTopic.feeding => 'feeding schedule',
    ChatTopic.waterQuality => 'water quality recommendations',
    ChatTopic.risks => 'possible risks',
  };

  String get label => switch (this) {
    ChatTopic.general => 'Pond assistant'.tr,
    ChatTopic.feeding => 'Feeding schedule'.tr,
    ChatTopic.waterQuality => 'Water quality'.tr,
    ChatTopic.risks => 'Possible risks'.tr,
  };

  IconData get icon => switch (this) {
    ChatTopic.general => Icons.auto_awesome,
    ChatTopic.feeding => Icons.set_meal_outlined,
    ChatTopic.waterQuality => Icons.tips_and_updates_outlined,
    ChatTopic.risks => Icons.warning_amber_outlined,
  };

  String get greeting => switch (this) {
    ChatTopic.general =>
      "Hi! I'm your pond assistant. Ask me about feeding, water quality or risks for this pond.".tr,
    ChatTopic.feeding =>
      'Ask me anything about when, how often and how much to feed your fish.'.tr,
    ChatTopic.waterQuality =>
      "Ask me how to read and improve your pond's water quality.".tr,
    ChatTopic.risks =>
      'Ask me what could go wrong in this pond and how to prevent it.'.tr,
  };

  List<String> get suggestions => switch (this) {
    ChatTopic.general => [
      'Is my pond healthy right now?'.tr,
      'What should I do today?'.tr,
      'Explain my readings'.tr,
    ],
    ChatTopic.feeding => [
      'Why this feeding time?'.tr,
      'What if I miss a feeding?'.tr,
      'Should I feed less when it is hot?'.tr,
    ],
    ChatTopic.waterQuality => [
      'How do I lower ammonia?'.tr,
      'How can I raise dissolved oxygen?'.tr,
      'Which reading should I fix first?'.tr,
    ],
    ChatTopic.risks => [
      'What is my biggest risk now?'.tr,
      'How do I prevent fish kills?'.tr,
      'What are signs of stressed fish?'.tr,
    ],
  };
}
