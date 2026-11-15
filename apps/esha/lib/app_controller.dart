import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services/korlix_api.dart';
import 'services/purchases.dart';
import 'services/vanity_sync.dart';

class ChatTurn {
  const ChatTurn(this.role, this.content, {this.requestId, this.prompt});
  final String role, content;
  final String? requestId, prompt;
  Json toJson() => {
    'role': role,
    'content': content.length > 1500 ? content.substring(0, 1500) : content,
  };
}

const eshaReportReasons = [
  'Unsafe advice',
  'Offensive or hateful',
  'Sexual or inappropriate',
  'Incorrect or misleading',
  'Other',
];

class AnswerReportEvidence {
  const AnswerReportEvidence({
    required this.answer,
    required this.question,
    required this.shortened,
  });
  final String answer, question;
  final bool shortened;
}

String _reportExcerpt(String value, int maximumEncodedBytes) {
  if (utf8.encode(jsonEncode(value)).length <= maximumEncodedBytes) {
    return value;
  }
  final runes = value.runes.toList();
  var low = 0, high = runes.length;
  while (low < high) {
    final midpoint = (low + high + 1) ~/ 2;
    final candidate = String.fromCharCodes(runes.take(midpoint));
    if (utf8.encode(jsonEncode(candidate)).length <= maximumEncodedBytes) {
      low = midpoint;
    } else {
      high = midpoint - 1;
    }
  }
  return String.fromCharCodes(runes.take(low));
}

enum SignupOutcome { signedIn, confirmationRequired }

class EshaController extends ChangeNotifier {
  EshaController({
    required this.catalog,
    required this.api,
    required this.sync,
    required this.purchases,
  }) {
    sync.addListener(_changed);
    purchases.addListener(_changed);
    api.onSessionInvalidated = () {
      unawaited(_accountLost());
    };
  }
  final Catalog catalog;
  final KorlixApi api;
  final VanitySync sync;
  final EshaPurchases purchases;
  bool initializing = true,
      authBusy = false,
      chatBusy = false,
      _disposed = false;
  String? authError, chatError, notice;
  List<ChatTurn> chat = [];
  Json? _pendingConsultation;
  String? _aiConsentUser;
  final Set<ChatTurn> _reporting = {};
  final Map<ChatTurn, String> _reportReceipts = {};
  int _accountEpoch = 0;
  int get accountEpoch => _accountEpoch;
  AuthSession? get session => api.session;
  Vanity get vanity => sync.value;
  Recommendation get recommendation => recommend(catalog, vanity);
  bool get hasPendingQuestion => _pendingConsultation != null;
  String? get pendingQuestion => _pendingConsultation?['question'] as String?;
  bool get aiSharingConsented =>
      api.session != null && _aiConsentUser == api.session!.userId;
  bool get pendingUsesPreferences =>
      _pendingConsultation?['preferences'] is Map;
  String? reportReceiptFor(ChatTurn turn) => _reportReceipts[turn];
  bool isReporting(ChatTurn turn) => _reporting.contains(turn);

  void setAiSharingConsent(bool allow) {
    _aiConsentUser = allow ? api.session?.userId : null;
    if (!allow) {
      chatError =
          'Sharing with OpenAI is off. New questions and retries are paused.';
    } else if (aiSharingConsented) {
      chatError = null;
    }
    _changed();
  }

  void _resetAccountPrivacy() {
    _aiConsentUser = null;
    _reporting.clear();
    _reportReceipts.clear();
  }

  bool _maySendToAi() {
    if (aiSharingConsented) return true;
    chatError = 'Choose whether to share your question and recent conversation with OpenAI before asking Esha or retrying.';
    _changed();
    return false;
  }

  String _pendingKey(String userId) => 'esha.consultation.pending.$userId';
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await sync.attach(null);
      await api.restoreSession();
      if (api.session != null) {
        await sync.attach(api.session!.userId);
        await _restorePending();
      }
    } catch (e) {
      notice = e is EshaException
          ? e.message
          : 'Account access is unavailable. You can keep exploring as a guest.';
    }
    initializing = false;
    _changed();
    await purchases.initialize();
  }

  Future<void> _restorePending() async {
    final user = api.session?.userId, epoch = _accountEpoch;
    if (user == null) return;
    try {
      final stored = await api.secureStorage.read(_pendingKey(user));
      if (stored == null ||
          user != api.session?.userId ||
          epoch != _accountEpoch) {
        return;
      }
      final pending = object(jsonDecode(stored));
      if (pending['requestId'] is String && pending['question'] is String) {
        _pendingConsultation = pending;
        chatError = 'A previous reply was not confirmed. Retry that question to retrieve its result safely.';
      }
    } catch (_) {
      /* A pending request is never replayed automatically. */
    }
  }

  Future<bool> signIn(String email, String password) async {
    if (authBusy) return false;
    final epoch = ++_accountEpoch;
    _resetAccountPrivacy();
    authBusy = true;
    authError = null;
    chat = [];
    _pendingConsultation = null;
    chatError = null;
    chatBusy = false;
    unawaited(sync.attach(null));
    _changed();
    try {
      final result = await api.signIn(email, password);
      if (epoch != _accountEpoch) return false;
      purchases.accountChanged();
      await sync.attach(result.userId);
      await _restorePending();
      if (epoch != _accountEpoch) return false;
      return true;
    } catch (e) {
      if (epoch == _accountEpoch) {
        authError = e is EshaException
            ? e.message
            : 'Korlix sign-in could not be completed.';
      }
      return false;
    } finally {
      if (epoch == _accountEpoch) {
        authBusy = false;
        _changed();
      }
    }
  }

  Future<SignupOutcome?> signUp(
    String email,
    String password, {
    required String ageBand,
    required bool termsAccepted,
    required bool privacyAcknowledged,
    required bool parentPermission,
  }) async {
    if (authBusy) return null;
    final epoch = ++_accountEpoch;
    _resetAccountPrivacy();
    authBusy = true;
    authError = null;
    chat = [];
    _pendingConsultation = null;
    chatError = null;
    chatBusy = false;
    unawaited(sync.attach(null));
    _changed();
    try {
      final result = await api.signUp(
        email,
        password,
        ageBand: ageBand,
        termsAccepted: termsAccepted,
        privacyAcknowledged: privacyAcknowledged,
        parentPermission: parentPermission,
      );
      if (epoch != _accountEpoch) return null;
      if (result == null) return SignupOutcome.confirmationRequired;
      purchases.accountChanged();
      await sync.attach(result.userId);
      await _restorePending();
      if (epoch != _accountEpoch) return null;
      return SignupOutcome.signedIn;
    } catch (e) {
      if (epoch == _accountEpoch) {
        authError = e is EshaException ? e.message : 'The account request could not be confirmed. Check your email or try signing in.';
      }
      return null;
    } finally {
      if (epoch == _accountEpoch) {
        authBusy = false;
        _changed();
      }
    }
  }

  Future<void> signOut() async {
    ++_accountEpoch;
    _resetAccountPrivacy();
    chat = [];
    chatError = null;
    _pendingConsultation = null;
    chatBusy = false;
    authError = null;
    final closing = api.signOut();
    purchases.accountChanged();
    unawaited(sync.attach(null));
    _changed();
    try {
      await closing;
    } catch (e) {
      notice = e is EshaException
          ? e.message
          : 'Signed out locally. Remote closure could not be confirmed.';
      _changed();
    }
  }

  Future<void> _accountLost() async {
    ++_accountEpoch;
    _resetAccountPrivacy();
    chat = [];
    _pendingConsultation = null;
    chatBusy = false;
    chatError = null;
    purchases.accountChanged();
    await sync.attach(null);
    notice = 'Your Korlix session ended. Sign in again to sync your account collection.';
    _changed();
  }

  void clearNotice() {
    notice = null;
    _changed();
  }

  void toggleFavorite(Product product) {
    final values = [...vanity.favorites];
    values.contains(product.id)
        ? values.remove(product.id)
        : values.add(product.id);
    if (values.length > 100) return;
    sync.update(vanity.copyWith(favorites: values));
  }

  void toggleOwned(Product product) {
    final values = [...vanity.owned];
    values.contains(product.id)
        ? values.remove(product.id)
        : values.add(product.id);
    if (values.length > 100) return;
    sync.update(vanity.copyWith(owned: values));
  }

  void setPreferences(BeautyPreferences prefs) =>
      sync.update(vanity.copyWith(prefs: prefs));
  void setProfile(BeautyProfile profile) =>
      sync.update(vanity.copyWith(beautyProfile: profile));
  void setStudio(StudioLook look) => sync.update(vanity.copyWith(studio: look));
  void saveRoutine() {
    final result = recommendation;
    if (!result.complete || !sync.canEdit) return;
    final saved = SavedRoutine(
      id: const Uuid().v4(),
      name: goals[vanity.prefs.goal]!.title,
      ids: result.items.map((p) => p.id).toList(),
      costCents: result.costCents,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      prefs: vanity.prefs,
      ownedAtSave: [...vanity.owned],
      items: result.items
          .map(
            (p) => {
              'id': p.id,
              'name': p.name,
              'brand': p.brand,
              'sourceUrl': p.sourceUrl,
              'priceCents': p.priceCents,
            },
          )
          .toList(),
    );
    sync.update(
      vanity.copyWith(routines: [saved, ...vanity.routines].take(30).toList()),
    );
  }

  void deleteRoutine(String id) => sync.update(
    vanity.copyWith(
      routines: vanity.routines.where((r) => r.id != id).toList(),
    ),
  );
  void saveLook() => sync.update(
    vanity.copyWith(
      looks: [
        vanity.studio.copyWith(id: const Uuid().v4()),
        ...vanity.looks,
      ].take(50).toList(),
    ),
  );
  void deleteLook(String id) => sync.update(
    vanity.copyWith(looks: vanity.looks.where((l) => l.id != id).toList()),
  );

  Future<void> ask(String question) async {
    if (chatBusy) return;
    if (_pendingConsultation != null) {
      chatError = 'Resolve your previous question before sending a new one.';
      _changed();
      return;
    }
    if (api.session == null) {
      chatError = 'Sign in to ask Esha a live beauty question.';
      _changed();
      return;
    }
    if (!_maySendToAi()) return;
    final text = question.trim();
    if (text.isEmpty || text.length > 3000) return;
    if (!purchases.membership.canConsult) {
      chatError = 'Check your Esha membership and available consultation allowance first.';
      _changed();
      return;
    }
    final prefs = vanity.prefs;
    _pendingConsultation = {
      'requestId': const Uuid().v4(),
      'question': text,
      'history': chat
          .skip(chat.length > 10 ? chat.length - 10 : 0)
          .map((t) => t.toJson())
          .toList(),
      if (vanity.beautyProfile.shareWithEsha)
        'preferences': {
          ...prefs.toJson(),
          'undertone': vanity.beautyProfile.undertone,
          'ownedProductIds': vanity.owned.take(12).toList(),
          'selectedProductIds': recommendation.items
              .map((p) => p.id)
              .take(12)
              .toList(),
        },
    };
    await retryQuestion();
  }

  Future<void> retryQuestion() async {
    if (chatBusy || _pendingConsultation == null || api.session == null) return;
    if (!_maySendToAi()) return;
    if (pendingUsesPreferences && !vanity.beautyProfile.shareWithEsha) {
      chatError = 'This saved question includes preferences you shared earlier. To retry its unchanged request, allow preference sharing in your profile first.';
      _changed();
      return;
    }
    final snapshot = api.owner(),
        epoch = _accountEpoch,
        request = _pendingConsultation!;
    chatBusy = true;
    chatError = null;
    _changed();
    try {
      // Persist the exact idempotency body before dispatch. A restart can recover
      // the same request; tokens and the pending question remain in secure storage.
      await api.secureStorage.write(
        _pendingKey(snapshot.userId),
        jsonEncode(request),
      );
      api.verifyOwner(snapshot);
      if (!aiSharingConsented) {
        throw const EshaException(
          'AI_CONSENT_REQUIRED',
          'Sharing with OpenAI is off. Your question remains paused.',
        );
      }
      if (request['preferences'] is Map &&
          !vanity.beautyProfile.shareWithEsha) {
        throw const EshaException(
          'AI_PREFERENCES_PAUSED',
          'Preference sharing is off. This saved question remains paused.',
        );
      }
      final result = await api.consult(request);
      api.verifyOwner(snapshot);
      if (epoch != _accountEpoch) return;
      final answer = result['answer'];
      if (answer is! String ||
          answer.trim().isEmpty ||
          result['requestId'] != request['requestId']) {
        throw const EshaException(
          'RESPONSE_UNCONFIRMED',
          'The reply could not be confirmed. Retry this question to check its result.',
        );
      }
      chat = [
        ...chat,
        ChatTurn('user', request['question'] as String),
        ChatTurn(
          'assistant',
          answer,
          requestId: request['requestId'] as String,
          prompt: request['question'] as String,
        ),
      ];
      if (chat.length > 30) chat = chat.sublist(chat.length - 30);
      purchases.applyAllowance(object(result['usage']));
      _pendingConsultation = null;
      await api.secureStorage.remove(_pendingKey(snapshot.userId));
    } catch (e) {
      if (!api.isOwner(snapshot) || epoch != _accountEpoch) return;
      final error = e is EshaException
          ? e
          : const EshaException(
              'NETWORK_ERROR',
              'The reply could not be confirmed.',
            );
      if (error.code == 'request_finished' ||
          error.code == 'invalid_request' ||
          error.status == 402 ||
          error.status == 403) {
        _pendingConsultation = null;
        await api.secureStorage.remove(_pendingKey(snapshot.userId));
        chatError = error.code == 'request_finished'
            ? 'That request finished without an available reply. You can send a new question when you are ready.'
            : error.message;
      } else if (error.code == 'idempotency_mismatch') {
        chatError = 'The saved request does not match the server copy. Refresh membership and contact Korlix support before resending.';
      } else {
        chatError = error.code == 'request_in_progress'
            ? 'Esha is still preparing this answer. Retry this same question shortly; its request ID is preserved.'
            : '${error.message} Retry this same question to check its result without creating another request.';
      }
    } finally {
      if (api.isOwner(snapshot) && epoch == _accountEpoch) {
        chatBusy = false;
        _changed();
      }
    }
  }

  AnswerReportEvidence reportEvidence(ChatTurn turn) {
    if (turn.role != 'assistant' ||
        !chat.contains(turn) ||
        turn.requestId == null ||
        turn.prompt == null) {
      throw const EshaException(
        'REPORT_UNAVAILABLE',
        'This answer is no longer available in the current account conversation.',
      );
    }
    // Leave room within the shared report endpoint's 32 KiB limit for the
    // user-selected details and server-supplied account/device metadata.
    final answer = _reportExcerpt(turn.content, 20000);
    final question = _reportExcerpt(turn.prompt!, 4000);
    return AnswerReportEvidence(
      answer: answer,
      question: question,
      shortened: answer != turn.content || question != turn.prompt,
    );
  }

  Future<String> reportAnswer(
    ChatTurn turn, {
    required String reason,
    required String details,
  }) async {
    final snapshot = api.owner(), evidence = reportEvidence(turn);
    if (!eshaReportReasons.contains(reason)) {
      throw const EshaException('REPORT_REASON', 'Choose a report reason.');
    }
    final notes = details.trim();
    if (utf8.encode(jsonEncode(notes)).length > 2000) {
      throw const EshaException(
        'REPORT_TOO_LARGE',
        'Please shorten the report details and try again.',
      );
    }
    final existing = _reportReceipts[turn];
    if (existing != null) return existing;
    if (!_reporting.add(turn)) {
      throw const EshaException('REPORT_PENDING', 'This report is being sent.');
    }
    _changed();
    try {
      final result = await api.reportOutput({
        'appArea': 'esha_by_korlix',
        'contentType': 'text',
        'contentId': turn.requestId,
        'outputSummary': evidence.answer,
        'prompt': evidence.question,
        'reason': reason,
        'details': notes,
        'appVersion': '1.0.0+1',
        'platform': api.platform,
      });
      api.verifyOwner(snapshot);
      final receipt = result['reportId'];
      if (result['ok'] != true ||
          receipt is! String ||
          !RegExp(r'^korlix_report_[A-Za-z0-9-]{1,100}$').hasMatch(receipt)) {
        throw const EshaException(
          'REPORT_UNCONFIRMED',
          'The service did not confirm a report reference. Your report may have arrived; contact support before resending.',
        );
      }
      _reportReceipts[turn] = receipt;
      return receipt;
    } finally {
      _reporting.remove(turn);
      _changed();
    }
  }

  Future<String> requestDeletion() async {
    final snapshot = api.owner();
    final result = await api.requestAccountDeletion(
      'Requested from Esha by Korlix native account settings',
    );
    api.verifyOwner(snapshot);
    if (result['success'] != true) {
      throw const EshaException(
        'DELETE_UNCONFIRMED',
        'The account-deletion request was not confirmed. Please retry later.',
      );
    }
    return 'Your Korlix account-deletion request was received. Manage any store subscription separately to stop future renewals.';
  }

  @override
  void dispose() {
    _disposed = true;
    ++_accountEpoch;
    sync.removeListener(_changed);
    purchases.removeListener(_changed);
    sync.dispose();
    purchases.dispose();
    api.dispose();
    super.dispose();
  }
}
