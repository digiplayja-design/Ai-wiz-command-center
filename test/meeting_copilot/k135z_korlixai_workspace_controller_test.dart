import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/k135z_copilot_contract.dart';
import '../../lib/meeting_copilot/k135z_workspace_controller.dart';
import 'helpers/k135z_korlixai_fakes.dart';

void main() {
  test(
    'start enters listening only after a matching authorized acknowledgment',
    () async {
      final K135zFakeGateway gateway = K135zFakeGateway();
      final K135zWorkspaceController controller = K135zWorkspaceController(
        gateway: gateway,
        context: k135zTestContext(),
        accessGranted: true,
      );

      final Future<bool> pending = controller.startListening();
      expect(controller.state.phase, K135zWorkspacePhase.starting);
      expect(controller.state.pendingAction, K135zWorkspaceAction.start);

      gateway.acknowledgeNext();
      expect(await pending, isTrue);
      expect(controller.state.phase, K135zWorkspacePhase.listening);
      expect(controller.state.canSpeak, isFalse);
      controller.dispose();
    },
  );

  test(
    'false or under-authorized acknowledgment cannot claim listening',
    () async {
      final K135zFakeGateway gateway = K135zFakeGateway();
      final K135zWorkspaceController controller = K135zWorkspaceController(
        gateway: gateway,
        context: k135zTestContext(),
        accessGranted: true,
      );

      final Future<bool> rejected = controller.startListening();
      gateway.acknowledgeNext(accepted: false, remoteState: 'unchanged');
      expect(await rejected, isFalse);
      expect(controller.state.phase, K135zWorkspacePhase.error);

      controller.replaceContext(
        k135zTestContext(
          generation: 2,
          sessionId: 'session-2',
          streamId: 'stream-2',
        ),
      );
      final Future<bool> unauthorized = controller.startListening();
      gateway.acknowledgeNext(listeningAuthorized: false, remoteState: 'ready');
      expect(await unauthorized, isFalse);
      expect(controller.state.phase, K135zWorkspacePhase.error);
      controller.dispose();
    },
  );

  test(
    'access loss invalidates immediately and rejects late completion',
    () async {
      final K135zFakeGateway gateway = K135zFakeGateway();
      final K135zWorkspaceController controller = K135zWorkspaceController(
        gateway: gateway,
        context: k135zTestContext(),
        accessGranted: true,
      );

      final Future<bool> pending = controller.startListening();
      controller.setAccessGranted(false);
      expect(controller.state.phase, K135zWorkspacePhase.locked);
      gateway.acknowledgeNext();
      expect(await pending, isFalse);
      expect(controller.state.phase, K135zWorkspacePhase.locked);
      controller.dispose();
    },
  );

  test('context replacement rejects a stale operation result', () async {
    final K135zFakeGateway gateway = K135zFakeGateway();
    final K135zWorkspaceController controller = K135zWorkspaceController(
      gateway: gateway,
      context: k135zTestContext(),
      accessGranted: true,
    );

    final Future<bool> pending = controller.startListening();
    controller.replaceContext(
      k135zTestContext(
        generation: 2,
        sessionId: 'session-2',
        streamId: 'stream-2',
      ),
    );
    gateway.acknowledgeNext();
    expect(await pending, isFalse);
    expect(controller.state.context.sessionId, 'session-2');
    expect(controller.state.phase, K135zWorkspacePhase.ready);
    controller.dispose();
  });

  test('ingestion requires an acknowledged listening state', () async {
    final K135zFakeGateway gateway = K135zFakeGateway();
    final K135zWorkspaceController controller = K135zWorkspaceController(
      gateway: gateway,
      context: k135zTestContext(),
      accessGranted: true,
    );

    expect(
      () => controller.ingest(k135zTestEvent(1)),
      throwsA(isA<K135zProtocolException>()),
    );

    final Future<bool> pending = controller.startListening();
    gateway.acknowledgeNext();
    await pending;
    controller.ingest(k135zTestEvent(1));
    expect(controller.state.transcript.segments, hasLength(1));
    controller.dispose();
  });

  test('disposing prevents late result restoration', () async {
    final K135zFakeGateway gateway = K135zFakeGateway();
    final K135zWorkspaceController controller = K135zWorkspaceController(
      gateway: gateway,
      context: k135zTestContext(),
      accessGranted: true,
    );

    final Future<bool> pending = controller.startListening();
    controller.dispose();
    gateway.acknowledgeNext();
    expect(await pending, isFalse);
  });
}
