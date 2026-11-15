import '../models.dart';
import 'korlix_api.dart';

const eshaVoiceModel = 'gpt-live-1';
final voiceRequestIdPattern = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
);

class VoiceUsage {
  const VoiceUsage({
    required this.limitSeconds,
    required this.usedSeconds,
    required this.reservedSeconds,
    required this.remainingSeconds,
    required this.deepLimit,
    required this.deepUsed,
    required this.deepReserved,
    required this.deepRemaining,
  });
  factory VoiceUsage.fromJson(Json value) {
    final voice = object(value['voice']), deep = object(value['deep']);
    int integer(Json data, String key) {
      final field = data[key];
      if (field is! int || field < 0 || field > 1000000) {
        throw const EshaException(
          'VOICE_RESPONSE',
          'Voice allowance could not be verified.',
        );
      }
      return field;
    }

    num seconds(String key) {
      final field = voice[key];
      if (field is! num || !field.isFinite || field < 0 || field > 1000000) {
        throw const EshaException(
          'VOICE_RESPONSE',
          'Voice allowance could not be verified.',
        );
      }
      return field;
    }

    final result = VoiceUsage(
      limitSeconds: integer(voice, 'limitSeconds'),
      usedSeconds: seconds('usedSeconds'),
      reservedSeconds: seconds('reservedSeconds'),
      remainingSeconds: seconds('remainingSeconds'),
      deepLimit: integer(deep, 'limit'),
      deepUsed: integer(deep, 'used'),
      deepReserved: integer(deep, 'reserved'),
      deepRemaining: integer(deep, 'remaining'),
    );
    if (result.remainingSeconds > result.limitSeconds ||
        result.deepRemaining > result.deepLimit) {
      throw const EshaException(
        'VOICE_RESPONSE',
        'Voice allowance could not be verified.',
      );
    }
    return result;
  }

  /// Provider usage can be fractional. Preserve it; only the displayed clock
  /// rounds down. Neither a 15-second initialization fee nor elapsed UI time is
  /// substituted for customer usage returned by the server.
  final int limitSeconds;
  final num usedSeconds, reservedSeconds, remainingSeconds;
  final int deepLimit, deepUsed, deepReserved, deepRemaining;

  static VoiceUsage? optional(Json value) {
    final voice = object(value['voice']);
    if (voice['configured'] == false && voice['limitSeconds'] == null) {
      return null;
    }
    return VoiceUsage.fromJson(value);
  }
}

class VoiceDeepResult {
  const VoiceDeepResult({
    required this.requestId,
    required this.answer,
    required this.productIds,
  });
  final String requestId, answer;
  final List<String> productIds;
  static List<VoiceDeepResult> parse(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.length > 10) {
      throw const EshaException(
        'VOICE_RESPONSE',
        'The saved deep-thinking answers could not be verified.',
      );
    }
    final result = <VoiceDeepResult>[];
    final seen = <String>{};
    for (final item in value) {
      final row = object(item), id = object(item)['requestId'];
      final answer = row['answer'], products = row['productIds'];
      if (id is! String ||
          !RegExp(
            r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[1-5][a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$',
          ).hasMatch(id) ||
          !seen.add(id) ||
          answer is! String ||
          answer.trim().isEmpty ||
          answer.length > 24000 ||
          products is! List ||
          products.length > 12 ||
          products.any(
            (product) =>
                product is! String || product.isEmpty || product.length > 200,
          )) {
        throw const EshaException(
          'VOICE_RESPONSE',
          'The saved deep-thinking answers could not be verified.',
        );
      }
      result.add(
        VoiceDeepResult(
          requestId: id,
          answer: answer,
          productIds: List<String>.unmodifiable(products),
        ),
      );
    }
    return List<VoiceDeepResult>.unmodifiable(result);
  }
}

class VoiceAvailability {
  const VoiceAvailability({
    required this.enabled,
    required this.usage,
    this.unavailabilityReason,
  });
  final bool enabled;
  final VoiceUsage? usage;
  final String? unavailabilityReason;
  bool get connectionLimitReached =>
      unavailabilityReason == 'voice_start_attempts_exhausted';
  factory VoiceAvailability.fromJson(Json value, DateTime now) {
    final membership = object(value['membership']);
    final expiresAt = membership['expiresAt'] is String
        ? DateTime.tryParse(membership['expiresAt'] as String)
        : null;
    final reason =
        value['unavailabilityReason'] == 'voice_start_attempts_exhausted'
        ? 'voice_start_attempts_exhausted'
        : null;
    final enabled =
        reason == null &&
        value['voiceEnabled'] == true &&
        value['model'] == eshaVoiceModel &&
        membership['active'] == true &&
        membership['verificationFresh'] == true &&
        expiresAt != null &&
        expiresAt.isAfter(now);
    VoiceUsage? usage;
    if (value['usage'] is Map) {
      usage = VoiceUsage.optional(object(value['usage']));
    }
    return VoiceAvailability(
      enabled: enabled && usage != null,
      usage: usage,
      unavailabilityReason: reason,
    );
  }
}

class VoiceSessionStatus {
  const VoiceSessionStatus({
    required this.requestId,
    required this.state,
    required this.finalizationConfirmed,
    required this.usage,
    this.deepResults = const [],
    this.sessionId,
    this.sdpAnswer,
  });
  factory VoiceSessionStatus.fromJson(
    Json value,
    String expectedId, {
    bool created = false,
  }) {
    final state = value['state'];
    final id = value['sessionId'];
    final answer = value['sdpAnswer'];
    if (value['requestId'] != expectedId ||
        !voiceRequestIdPattern.hasMatch(expectedId) ||
        state is! String ||
        !{
          'starting',
          'active',
          'closing',
          'closed',
          'uncertain',
        }.contains(state) ||
        value['finalizationConfirmed'] is! bool ||
        (value['finalizationConfirmed'] == true && state != 'closed') ||
        (created &&
            (value['model'] != eshaVoiceModel ||
                !{'starting', 'active'}.contains(state) ||
                id is! String ||
                id.isEmpty ||
                id.length > 256 ||
                answer is! String ||
                !answer.startsWith('v=0') ||
                answer.length > 65536))) {
      throw const EshaException(
        'VOICE_RESPONSE',
        'The voice session could not be verified.',
      );
    }
    final usage = VoiceUsage.optional(object(value['usage']));
    if (created && usage == null) {
      throw const EshaException(
        'VOICE_RESPONSE',
        'The voice allowance could not be verified.',
      );
    }
    return VoiceSessionStatus(
      requestId: expectedId,
      state: state,
      finalizationConfirmed: value['finalizationConfirmed'] == true,
      usage: usage,
      deepResults: VoiceDeepResult.parse(value['deepResults']),
      sessionId: id is String ? id : null,
      sdpAnswer: created ? answer as String : null,
    );
  }
  final String requestId, state;
  final String? sessionId, sdpAnswer;
  final bool finalizationConfirmed;
  final VoiceUsage? usage;
  final List<VoiceDeepResult> deepResults;
  bool get finalized => state == 'closed' && finalizationConfirmed;
}

abstract interface class VoiceGateway {
  Future<VoiceAvailability> availability();
  Future<VoiceSessionStatus> create({
    required String requestId,
    required String sdpOffer,
    required bool deepThinkingConsent,
  });
  Future<VoiceSessionStatus> status(String requestId);
  Future<VoiceSessionStatus> stop(String requestId, String reason);
}

/// Every request uses Korlix account authentication. No provider URL, model
/// override, API key or billing balance can be supplied by the native caller.
class KorlixVoiceGateway implements VoiceGateway {
  KorlixVoiceGateway(this.api);
  final KorlixApi api;
  @override
  Future<VoiceAvailability> availability() async => VoiceAvailability.fromJson(
    await api.authenticated(
      'GET',
      '/api/esha/voice/status?provider=${api.provider}',
      retryUnauthorized: true,
    ),
    DateTime.now().toUtc(),
  );

  String _path(String requestId) {
    if (!voiceRequestIdPattern.hasMatch(requestId)) {
      throw const EshaException(
        'VOICE_REQUEST',
        'The saved voice request is invalid.',
      );
    }
    return '/api/esha/voice/sessions/$requestId';
  }

  @override
  Future<VoiceSessionStatus> create({
    required String requestId,
    required String sdpOffer,
    required bool deepThinkingConsent,
  }) async {
    _path(requestId);
    final value = await api.authenticated(
      'POST',
      '/api/esha/voice/sessions',
      body: {
        'requestId': requestId,
        'sdpOffer': sdpOffer,
        'audioSharingConsent': true,
        'deepThinkingConsent': deepThinkingConsent,
      },
      // Never replay a session creation, including after an unauthorized result.
      retryUnauthorized: false,
      timeout: const Duration(seconds: 30),
    );
    return VoiceSessionStatus.fromJson(value, requestId, created: true);
  }

  @override
  Future<VoiceSessionStatus> status(String requestId) async =>
      VoiceSessionStatus.fromJson(
        await api.authenticated(
          'GET',
          _path(requestId),
          retryUnauthorized: true,
        ),
        requestId,
      );

  @override
  Future<VoiceSessionStatus> stop(String requestId, String reason) async {
    if (!{
      'user_stop',
      'paused',
      'background',
      'transport_error',
    }.contains(reason)) {
      throw const EshaException(
        'VOICE_REQUEST',
        'The voice stop request is invalid.',
      );
    }
    return VoiceSessionStatus.fromJson(
      await api.authenticated(
        'POST',
        '${_path(requestId)}/stop',
        body: {'reason': reason},
        retryUnauthorized: false,
        timeout: const Duration(seconds: 10),
      ),
      requestId,
    );
  }
}
