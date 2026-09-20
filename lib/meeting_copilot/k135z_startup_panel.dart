import 'package:flutter/material.dart';

import 'k135z_feedback_button.dart';
import 'k135z_zoom_runtime_binding.dart';

class K135zStartupPanel extends StatelessWidget {
const K135zStartupPanel({super.key, required this.binding});
final K135zZoomRuntimeBinding? binding;

@override
Widget build(BuildContext context) {
final b = binding, c = binding?.capture;
final available = b != null && b.usable && !b.busy;
final selected = c?.meetingUuid != null && c?.statusLabel != 'Stopped';
final listening = c?.statusLabel == 'Listening';
final resume =
selected &&
!listening &&
!['Ready', 'No session selected'].contains(c?.statusLabel);
const muted = Color(0xFF9CB8CA), cyan = Color(0xFF22D8FF);
return Material(
color: const Color(0xFF0A223A),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(18),
side: const BorderSide(color: Color(0xFF1A5872)),
),
child: Padding(
padding: const EdgeInsets.all(18),
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
const Text(
'Your meeting',
style: TextStyle(
color: Colors.white,
fontSize: 22,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 6),
Text(
b == null
? 'Open Meeting Copilot from your selected agent in Agent Hub.'
: b.connected
? 'Zoom connected · Choose your meeting below.'
: b.message,
key: const Key('g6c-connection-message'),
style: const TextStyle(color: muted),
),
const SizedBox(height: 14),
if (b != null && b.connected) ...[
if (b.meetings.isEmpty)
Text(
b.busy ? 'Loading your meetings…' : 'No meetings found. Start your meeting in Zoom, then refresh the list.',
style: const TextStyle(color: muted),
),
Wrap(
spacing: 8,
runSpacing: 8,
children: [
for (final meeting in b.meetings)
K135zFeedbackButton.outlined(
selected:
meeting.uuid != null &&
c!.isMeetingSelected(meeting.uuid!),
pendingLabel: 'Selecting…',
onPressed:
available &&
!c!.busy &&
meeting.uuid != null &&
!c.isMeetingSelected(meeting.uuid!)
? () => c.selectMeeting(meeting.uuid!)
: null,
child: Text(
'${meeting.topic}${meeting.uuid == null
? " · Unavailable"
: c!.isMeetingSelected(meeting.uuid!)
? " · Selected"
: ""}',
),
),
],
),
if (selected) ...[
CheckboxListTile(
key: const Key('g6n-consent'),
contentPadding: EdgeInsets.zero,
controlAffinity: ListTileControlAffinity.leading,
title: const Text(
'I consent to listening and transcription for this meeting.',
style: TextStyle(color: Colors.white),
),
subtitle: const Text(
'Remembered for this meeting until you stop Nova or withdraw consent.',
style: TextStyle(color: muted),
),
value: c!.consent,
onChanged: c.usable && !c.busy
? (value) => c.setConsent(value == true)
: null,
),
Wrap(
spacing: 10,
runSpacing: 10,
children: [
K135zFeedbackButton.filled(
buttonKey: const Key('start-listening-button'),
selected: listening,
activeColor: const Color(0xFF63E6A1),
pendingLabel: 'Connecting Nova…',
onPressed: available && c.canStart ? c.start : null,
child: Text(
listening
? 'Nova is listening'
: resume
? 'Resume Nova Copilot'
: 'Start Nova Copilot',
),
),
if (listening)
K135zFeedbackButton.outlined(
buttonKey: const Key('pause-listening-button'),
pendingLabel: 'Pausing…',
onPressed: c.canPause ? c.pause : null,
child: const Text('Pause Nova'),
),
K135zFeedbackButton.outlined(
buttonKey: const Key('stop-listening-button'),
pendingLabel: 'Stopping…',
onPressed: c.canStop ? c.stop : null,
child: const Text('Stop Copilot'),
),
],
),
const SizedBox(height: 12),
Semantics(
liveRegion: true,
child: Text(
c.listeningMessage,
key: const Key('g6n-session-message'),
style: TextStyle(
color: c.actionError == null
? cyan
: const Color(0xFFFFA2A2),
),
),
),
],
] else if (b != null) ...[
K135zFeedbackButton.filled(
buttonKey: const Key('g6c-connect'),
onPressed: b.canOpenAuthorization
? b.openAuthorization
: available
? b.prepareAuthorization
: null,
pendingLabel: 'Preparing Zoom…',
child: Text(
b.canOpenAuthorization ? 'Continue to Zoom' : 'Connect Zoom',
),
),
],
const SizedBox(height: 10),
ExpansionTile(
key: const Key('copilot-connection-options'),
tilePadding: EdgeInsets.zero,
childrenPadding: const EdgeInsets.only(bottom: 8),
title: const Text(
'Connection options',
style: TextStyle(color: muted, fontSize: 14),
),
children: [
Wrap(
spacing: 8,
runSpacing: 8,
children: [
K135zFeedbackButton.outlined(
buttonKey: const Key('g6c-refresh'),
onPressed: available ? b.initialize : null,
pendingLabel: 'Checking…',
child: const Text('Refresh connection & meetings'),
),
if (b != null && b.connected)
K135zFeedbackButton.outlined(
buttonKey: const Key('g6c-prepare'),
onPressed: available ? b.prepareAuthorization : null,
child: const Text('Reconnect Zoom'),
),
if (b?.canOpenAuthorization == true)
K135zFeedbackButton.outlined(
buttonKey: const Key('g6c-open'),
onPressed: b!.openAuthorization,
child: const Text('Continue to Zoom'),
),
if (c != null && selected)
K135zFeedbackButton.outlined(
buttonKey: const Key('g6n-refresh-session'),
onPressed: c.usable && !c.busy ? c.refresh : null,
child: const Text('Check session'),
),
if (b != null && b.connected)
K135zFeedbackButton.outlined(
buttonKey: const Key('g6c-disconnect'),
onPressed: available ? b.disconnect : null,
child: const Text('Disconnect Zoom'),
),
],
),
],
),
const Text(
'Keep this page visible while Nova listens. After switching apps, return here and tap Resume if shown.',
style: TextStyle(color: muted, fontSize: 12),
),
],
),
),
);
}
}
