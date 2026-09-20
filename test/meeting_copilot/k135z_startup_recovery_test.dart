import 'package:flutter_test/flutter_test.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;

void main() {
test('expired lease does not erase meeting consent on each timer tick', () async {
final f = CaptureFixture();
addTearDown(f.c.dispose);
await f.start();
f.row['validForMs'] = 0;
f.now = 31000;
await f.c.tick();
expect(f.c.statusLabel, 'Capture interrupted');
expect(f.c.consent, isTrue);
await f.c.setConsent(true);
f.now = 32000;
await f.c.tick();
expect(f.c.consent, isTrue);
expect(f.c.canStart, isTrue);
expect(f.calls.where((x) => x == 'start').length, 1);
expect(f.calls, isNot(contains('renew')));
await f.c.start();
expect(f.calls.takeLast(4), ['status', 'pause', 'consent', 'start']);
expect(f.c.statusLabel, 'Listening');
});

test('failed renewal preserves choice and needs a single explicit resume', () async {
final f = CaptureFixture();
addTearDown(f.c.dispose);
await f.start();
f.failRenew = true;
f.now = 10000;
await f.c.tick();
expect(f.c.statusLabel, 'Session unconfirmed');
expect(f.c.consent, isTrue);
final before = f.calls.length;
f.now = 20000;
await f.c.tick();
expect(f.calls.length, before);
await f.c.start();
expect(f.calls.takeLast(4), ['status', 'pause', 'consent', 'start']);
expect(f.c.statusLabel, 'Listening');
});

test('returning from Zoom rechecks status without silently starting or renewing', () async {
final f = CaptureFixture();
addTearDown(f.c.dispose);
await f.start();
f.c.suspend();
expect(f.c.consent, isTrue);
expect(f.c.canStart, isFalse);
final before = f.calls.length;
await f.c.resume();
expect(f.calls.skip(before), ['status']);
expect(f.c.canStart, isTrue);
expect(f.c.statusLabel, isNot('Listening'));
await f.c.start();
expect(f.c.statusLabel, 'Listening');
});

test('same meeting selection and Pause retain choice; Stop clears it', () async {
final f = CaptureFixture();
addTearDown(f.c.dispose);
await f.start();
await f.c.selectMeeting('meeting');
expect(f.c.consent, isTrue);
expect(f.c.statusLabel, 'Listening');
await f.c.pause();
expect(f.c.consent, isTrue);
expect(f.c.canStart, isTrue);
await f.c.start();
await f.c.stop();
expect(f.c.consent, isFalse);
expect(f.c.canStart, isFalse);
});

test('remote revocation and identity loss clear the meeting choice', () async {
final f = CaptureFixture();
addTearDown(f.c.dispose);
await f.start();
f.row['authorityRevision']++;
f.row['authority']['listeningAuthorized'] = false;
f.row['authority']['hostAuthorized'] = false;
f.row['validForMs'] = 0;
await f.c.refresh();
expect(f.c.consent, isFalse);
expect(f.c.statusLabel, isNot('Listening'));
await f.c.setConsent(true);
f.current = false;
await f.c.tick();
expect(f.c.consent, isFalse);
expect(f.c.canStart, isFalse);
});

test('a changed meeting never inherits consent or receives a recovered Start', () async {
final f = CaptureFixture();
addTearDown(f.c.dispose);
await f.start();
f.c.suspend();
f.row['snapshot']['context']['meetingUuid'] = 'another-meeting';
await f.c.resume();
final before = f.calls.where((x) => x == 'start').length;
await f.c.start();
expect(f.calls.where((x) => x == 'start').length, before);
expect(f.c.statusLabel, 'Session unconfirmed');
expect(f.c.consent, isFalse);
});

test('withdrawn consent cannot be restored by foreground status checks', () async {
final f = CaptureFixture();
addTearDown(f.c.dispose);
await f.start();
await f.c.setConsent(false);
f.c.suspend();
await f.c.resume();
await f.c.start();
expect(f.c.consent, isFalse);
expect(f.calls.where((x) => x == 'start').length, 1);
});
}

extension on List<String> {
List<String> takeLast(int count) => sublist(length - count);
}
