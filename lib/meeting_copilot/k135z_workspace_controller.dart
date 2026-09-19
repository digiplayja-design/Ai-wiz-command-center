import 'dart:async';

import 'package:flutter/foundation.dart';

import 'k135z_copilot_contract.dart';
import 'k135z_minutes_preview.dart';
import 'k135z_notes_projection.dart';
import 'k135z_transcript_reducer.dart';

abstract interface class K135zWorkspaceGateway {
  Future<K135zWorkspaceAck> execute(K135zWorkspaceCommand command);
}

@immutable
class K135zWorkspaceState {
  K135zWorkspaceState({
    required this.context,
    required this.phase,
    required this.accessGranted,
    required this.pendingAction,
    required this.transcript,
    required this.notes,
    required this.preview,
    required this.remoteState,
    required this.errorMessage,
    required this.operationRevision,
  });

  factory K135zWorkspaceState.initial({
    required K135zMeetingContext context,
    required bool accessGranted,
  }) => K135zWorkspaceState(
    context: context,
    phase: accessGranted
        ? K135zWorkspacePhase.ready
        : K135zWorkspacePhase.locked,
    accessGranted: accessGranted,
    pendingAction: null,
    transcript: K135zTranscriptReducer.initial(context),
    notes: null,
    preview: null,
    remoteState: accessGranted ? 'ready' : 'locked',
    errorMessage: null,
    operationRevision: 0,
  );

  final K135zMeetingContext context;
  final K135zWorkspacePhase phase;
  final bool accessGranted;
  final K135zWorkspaceAction? pendingAction;
  final K135zTranscriptState transcript;
  final K135zNotesResult? notes;
  final K135zMinutesPreview? preview;
  final String remoteState;
  final String? errorMessage;
  final int operationRevision;

  bool get canSpeak => false;
  bool get canStart =>
      accessGranted &&
      pendingAction == null &&
      <K135zWorkspacePhase>{
        K135zWorkspacePhase.ready,
        K135zWorkspacePhase.paused,
        K135zWorkspacePhase.stopped,
      }.contains(phase);
  bool get canPause =>
      accessGranted &&
      pendingAction == null &&
      phase == K135zWorkspacePhase.listening;
  bool get canStop =>
      accessGranted &&
      pendingAction == null &&
      <K135zWorkspacePhase>{
        K135zWorkspacePhase.listening,
        K135zWorkspacePhase.paused,
      }.contains(phase);

  K135zWorkspaceState copyWith({
    K135zMeetingContext? context,
    K135zWorkspacePhase? phase,
    bool? accessGranted,
    Object? pendingAction = _sentinel,
    K135zTranscriptState? transcript,
    Object? notes = _sentinel,
    Object? preview = _sentinel,
    String? remoteState,
    Object? errorMessage = _sentinel,
    int? operationRevision,
  }) => K135zWorkspaceState(
    context: context ?? this.context,
    phase: phase ?? this.phase,
    accessGranted: accessGranted ?? this.accessGranted,
    pendingAction: identical(pendingAction, _sentinel)
        ? this.pendingAction
        : pendingAction as K135zWorkspaceAction?,
    transcript: transcript ?? this.transcript,
    notes: identical(notes, _sentinel)
        ? this.notes
        : notes as K135zNotesResult?,
    preview: identical(preview, _sentinel)
        ? this.preview
        : preview as K135zMinutesPreview?,
    remoteState: remoteState ?? this.remoteState,
    errorMessage: identical(errorMessage, _sentinel)
        ? this.errorMessage
        : errorMessage as String?,
    operationRevision: operationRevision ?? this.operationRevision,
  );
}

const Object _sentinel = Object();

class K135zWorkspaceController extends ChangeNotifier {
  K135zWorkspaceController({
    required K135zWorkspaceGateway gateway,
    required K135zMeetingContext context,
    bool accessGranted = false,
  }) : _gateway = gateway,
       _state = K135zWorkspaceState.initial(
         context: context,
         accessGranted: accessGranted,
       );

  final K135zWorkspaceGateway _gateway;
  K135zWorkspaceState _state;
  int _operationSequence = 0;
  int _epoch = 0;
  bool _disposed = false;

  K135zWorkspaceState get state => _state;

  void setAccessGranted(bool granted) {
    if (_disposed || _state.accessGranted == granted) {
      return;
    }
    _epoch += 1;
    if (!granted) {
      _setState(
        K135zWorkspaceState.initial(
          context: _state.context,
          accessGranted: false,
        ).copyWith(
          operationRevision: _state.operationRevision + 1,
          errorMessage: 'Enterprise Meeting Copilot access is unavailable.',
        ),
      );
      return;
    }
    _setState(
      K135zWorkspaceState.initial(
        context: _state.context,
        accessGranted: true,
      ).copyWith(operationRevision: _state.operationRevision + 1),
    );
  }

  void replaceContext(K135zMeetingContext context) {
    if (_disposed || context == _state.context) {
      return;
    }
    _epoch += 1;
    _setState(
      K135zWorkspaceState.initial(
        context: context,
        accessGranted: _state.accessGranted,
      ).copyWith(operationRevision: _state.operationRevision + 1),
    );
  }

  Future<bool> startListening() => _runAction(
    action: K135zWorkspaceAction.start,
    pendingPhase: K135zWorkspacePhase.starting,
    allowed: state.canStart,
  );

  Future<bool> pauseListening() => _runAction(
    action: K135zWorkspaceAction.pause,
    pendingPhase: K135zWorkspacePhase.pausing,
    allowed: state.canPause,
  );

  Future<bool> stopListening() => _runAction(
    action: K135zWorkspaceAction.stop,
    pendingPhase: K135zWorkspacePhase.stopping,
    allowed: state.canStop,
  );

  Future<bool> disconnect() => _runAction(
    action: K135zWorkspaceAction.disconnect,
    pendingPhase: K135zWorkspacePhase.disconnecting,
    allowed: state.accessGranted && state.pendingAction == null,
  );

  void ingest(K135zTranscriptEvent event) {
    if (_disposed || !_state.accessGranted) {
      return;
    }
    if (_state.phase != K135zWorkspacePhase.listening) {
      throw const K135zProtocolException(
        'K135Z_INGEST_NOT_AUTHORIZED',
        'Transcript ingestion requires an acknowledged listening session.',
      );
    }
    final K135zTranscriptState transcript = K135zTranscriptReducer.ingest(
      _state.transcript,
      event,
    );
    final K135zNotesResult? notes = _state.notes == null
        ? null
        : K135zNotesProjection.reconcile(transcript, _state.notes!);
    _setState(
      _state.copyWith(
        transcript: transcript,
        notes: notes,
        preview: null,
        operationRevision: _state.operationRevision + 1,
      ),
    );
  }

  K135zNotesRequest? prepareNotes(String requestId) =>
      K135zNotesProjection.prepare(_state.transcript, requestId: requestId);

  void acceptNotes({
    required K135zNotesRequest request,
    required Iterable<K135zDraftInsight> draft,
    K135zMeetingMetadata? metadata,
  }) {
    if (_disposed || !_state.accessGranted) {
      return;
    }
    final K135zNotesResult notes = K135zNotesProjection.accept(
      transcript: _state.transcript,
      request: request,
      draft: draft,
    );
    final K135zMinutesPreview? preview = metadata == null
        ? null
        : K135zMinutesProjector.project(notes: notes, metadata: metadata);
    _setState(
      _state.copyWith(
        notes: notes,
        preview: preview,
        operationRevision: _state.operationRevision + 1,
      ),
    );
  }

  void updatePreview(K135zMeetingMetadata metadata) {
    final K135zNotesResult? notes = _state.notes;
    if (notes == null) {
      return;
    }
    _setState(
      _state.copyWith(
        preview: K135zMinutesProjector.project(
          notes: notes,
          metadata: metadata,
        ),
        operationRevision: _state.operationRevision + 1,
      ),
    );
  }

  Future<bool> _runAction({
    required K135zWorkspaceAction action,
    required K135zWorkspacePhase pendingPhase,
    required bool allowed,
  }) async {
    if (_disposed || !allowed) {
      return false;
    }
    final int epoch = _epoch;
    final int sequence = ++_operationSequence;
    final String operationId = '${_state.context.sessionId}:$sequence';
    final K135zWorkspaceCommand command = K135zWorkspaceCommand(
      operationId: operationId,
      context: _state.context,
      action: action,
    );
    _setState(
      _state.copyWith(
        phase: pendingPhase,
        pendingAction: action,
        errorMessage: null,
        operationRevision: _state.operationRevision + 1,
      ),
    );

    try {
      final K135zWorkspaceAck ack = await _gateway.execute(command);
      if (!_isCurrent(epoch, operationId, ack)) {
        return false;
      }
      if (!ack.accepted) {
        _setState(
          _state.copyWith(
            phase: K135zWorkspacePhase.error,
            pendingAction: null,
            remoteState: ack.remoteState,
            errorMessage: 'The remote operation was not acknowledged.',
            operationRevision: _state.operationRevision + 1,
          ),
        );
        return false;
      }

      final K135zWorkspacePhase phase = switch (action) {
        K135zWorkspaceAction.start
            when ack.hostAuthorized && ack.listeningAuthorized =>
          K135zWorkspacePhase.listening,
        K135zWorkspaceAction.start => K135zWorkspacePhase.error,
        K135zWorkspaceAction.pause => K135zWorkspacePhase.paused,
        K135zWorkspaceAction.stop => K135zWorkspacePhase.stopped,
        K135zWorkspaceAction.disconnect => K135zWorkspacePhase.disconnected,
      };
      final String? error =
          action == K135zWorkspaceAction.start &&
              phase != K135zWorkspacePhase.listening
          ? 'Host and listening authorization were not acknowledged.'
          : null;
      _setState(
        _state.copyWith(
          phase: phase,
          pendingAction: null,
          remoteState: ack.remoteState,
          errorMessage: error,
          operationRevision: _state.operationRevision + 1,
        ),
      );
      return error == null;
    } catch (error) {
      if (_disposed || epoch != _epoch) {
        return false;
      }
      _setState(
        _state.copyWith(
          phase: K135zWorkspacePhase.error,
          pendingAction: null,
          remoteState: 'unknown',
          errorMessage: error is K135zProtocolException
              ? error.message
              : 'The remote operation outcome is unknown.',
          operationRevision: _state.operationRevision + 1,
        ),
      );
      return false;
    }
  }

  bool _isCurrent(int epoch, String operationId, K135zWorkspaceAck ack) =>
      !_disposed &&
      epoch == _epoch &&
      ack.operationId == operationId &&
      ack.context == _state.context &&
      _state.accessGranted;

  void _setState(K135zWorkspaceState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch += 1;
    super.dispose();
  }
}
