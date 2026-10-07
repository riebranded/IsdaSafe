import 'package:flutter/foundation.dart';

import '../l10n/tr.dart';

import '../models/chat_message.dart';
import '../models/feeding_recommendation.dart';
import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../models/reading_status.dart';
import '../models/sensor_reading.dart';
import '../services/pond_chat_service.dart';
import 'dashboard_provider.dart';

/// One pond's conversation with the assistant.
///
/// Instances are kept per pond ([forPond]) for the app's lifetime, so closing
/// the chat sheet or leaving the dashboard doesn't lose the conversation.
class PondChatProvider extends ChangeNotifier {
  PondChatProvider({PondChatService? service})
    : _service = service ?? SupabasePondChatService();

  static final Map<String, PondChatProvider> _sessions = {};

  static PondChatProvider forPond(String pondId) =>
      _sessions.putIfAbsent(pondId, PondChatProvider.new);

  @visibleForTesting
  static void resetSessions() => _sessions.clear();

  final PondChatService _service;
  final List<ChatMessage> _messages = [];
  bool _sending = false;
  String? _error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get sending => _sending;
  String? get error => _error;

  /// Appends [text] as a user message and fetches the reply. [context] is
  /// built lazily so the model always sees the freshest readings.
  Future<void> send(
    String text, {
    required ChatTopic topic,
    required Map<String, Object?> Function() context,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    _messages.add(ChatMessage(role: ChatRole.user, text: trimmed));
    await _requestReply(topic, context);
  }

  /// Re-asks after a failed reply, without duplicating the user's message.
  Future<void> retry({
    required ChatTopic topic,
    required Map<String, Object?> Function() context,
  }) async {
    if (_sending || _messages.isEmpty || !_messages.last.isUser) return;
    await _requestReply(topic, context);
  }

  void clear() {
    if (_sending) return;
    _messages.clear();
    _error = null;
    notifyListeners();
  }

  Future<void> _requestReply(
    ChatTopic topic,
    Map<String, Object?> Function() context,
  ) async {
    _sending = true;
    _error = null;
    notifyListeners();
    try {
      final reply = await _service.send(
        messages: List.of(_messages),
        context: context(),
        topic: topic,
      );
      _messages.add(ChatMessage(role: ChatRole.assistant, text: reply));
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '').tr;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }
}

/// Snapshot of [pond] sent with every question so answers refer to its real
/// readings, species and the advice already shown on the dashboard.
/// [feeding] is the per-species advice fetched so far (possibly empty).
Map<String, Object?> buildPondChatContext(
  Pond pond, {
  Map<MetricType, SensorReading>? readings,
  Map<String, FeedingRecommendation> feeding = const {},
}) {
  return {
    'pond_name': pond.name,
    'species': pond.speciesNames,
    if (readings != null) ...{
      'overall_status': overallStatus(readings).label,
      'readings': {
        for (final entry in readings.entries)
          entry.key.label: entry.key.format(entry.value.value),
      },
    },
    'feeding_plans': {
      for (final entry in feeding.entries)
        entry.key: {
          'feeding_time': entry.value.feedingTime,
          'frequency': entry.value.feedingFrequency,
          'amount': entry.value.feedingAmount,
        },
    },
    'water_quality_recommendations': {
      for (final r in feeding.values) ...r.waterQualityRecommendations,
    }.toList(),
    'possible_risks': {
      for (final r in feeding.values) ...r.possibleRisks,
    }.toList(),
  };
}

/// [buildPondChatContext] from a pond dashboard's live state.
Map<String, Object?> pondChatContextFromDashboard(
  Pond pond,
  DashboardProvider dashboard,
) => buildPondChatContext(
  pond,
  readings: dashboard.snapshot?.readings,
  feeding: dashboard.feedingRecommendations,
);
