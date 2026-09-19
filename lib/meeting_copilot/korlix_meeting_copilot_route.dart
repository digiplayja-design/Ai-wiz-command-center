import 'dart:async';

import 'package:flutter/material.dart';

import 'k135z_workspace_controller.dart';
import 'k135z_zoom_runtime_binding.dart';
import 'korlix_meeting_copilot.dart';
import 'korlix_meeting_copilot_access.dart';
import 'korlix_zoom_connection_client.dart';

abstract final class KorlixMeetingCopilotAssets {
  static const String korlixLogo = 'assets/meeting_copilot/korlix_logo.jpeg';
  static const String novaPortrait = 'assets/meeting_copilot/nova_canonical.webp';
}

class KorlixMeetingCopilotRoute extends StatefulWidget {
  const KorlixMeetingCopilotRoute({super.key, this.workspaceController,
      this.zoomLaunch, this.zoomTransport, this.zoomOpenUrl});
  static const String routeName = '/meeting-copilot';
  static const Key screenKey = Key('korlix-meeting-copilot-route');
  static const String accessibilityLabel =
      'Nova Meeting Copilot. Nova is still muted by default until the host invites her.';
  final K135zWorkspaceController? workspaceController;
  final K135zZoomLaunch? zoomLaunch;
  final KorlixZoomJsonTransport? zoomTransport;
  final Future<bool> Function(Uri)? zoomOpenUrl;
  @override
  State<KorlixMeetingCopilotRoute> createState() => _KorlixMeetingCopilotRouteState();
}

class _KorlixMeetingCopilotRouteState extends State<KorlixMeetingCopilotRoute> with WidgetsBindingObserver {
  late final NovaMeetingCopilotController _controller;
  K135zZoomRuntimeBinding? _binding;
  K135zZoomLaunch? _launch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = NovaMeetingCopilotController();
    kKorlixMeetingCopilotEnterpriseAccess.addListener(_syncAccess);
    widget.workspaceController?.setAccessGranted(kKorlixMeetingCopilotEnterpriseAccess.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    final launch = widget.zoomLaunch ?? (args is K135zZoomLaunch ? args : null);
    if (!identical(launch, _launch)) _bind(launch);
  }

  void _bind(K135zZoomLaunch? launch) {
    _binding?.removeListener(_changed);
    _binding?.dispose();
    _binding = null;
    _launch = launch;
    _controller.setConnection(connected: false);
    if (launch != null && kKorlixMeetingCopilotEnterpriseAccess.value && launch.current) {
      _binding = K135zZoomRuntimeBinding(launch: launch,
          transport: widget.zoomTransport, openUrl: widget.zoomOpenUrl);
      _binding!.addListener(_changed);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { _binding?.capture.resume(); }
    else { _binding?.capture.suspend(); }
  }

  void _syncAccess() {
    final access = kKorlixMeetingCopilotEnterpriseAccess.value;
    widget.workspaceController?.setAccessGranted(access);
    if (!access) _binding?.invalidate();
    _changed();
  }

  void _changed() {
    if (!mounted) return;
    final connected = _binding?.connected == true &&
        kKorlixMeetingCopilotEnterpriseAccess.value;
    if (_controller.state.zoomConnected != connected) {
      _controller.setConnection(connected: connected);
    }
    if (_binding != null && !_binding!.usable) {
      widget.workspaceController?.setAccessGranted(false);
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant KorlixMeetingCopilotRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceController != widget.workspaceController) {
      oldWidget.workspaceController?.setAccessGranted(false);
      widget.workspaceController?.setAccessGranted(kKorlixMeetingCopilotEnterpriseAccess.value);
    }
    if (!identical(oldWidget.zoomLaunch, widget.zoomLaunch) ||
        !identical(oldWidget.zoomTransport, widget.zoomTransport) ||
        !identical(oldWidget.zoomOpenUrl, widget.zoomOpenUrl)) {
      final args = ModalRoute.of(context)?.settings.arguments;
      _bind(widget.zoomLaunch ?? (args is K135zZoomLaunch ? args : null));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    kKorlixMeetingCopilotEnterpriseAccess.removeListener(_syncAccess);
    _binding?.removeListener(_changed);
    _binding?.dispose();
    widget.workspaceController?.setAccessGranted(false);
    _controller.dispose();
    super.dispose();
  }

  Widget _connectionPanel() {
    final b = _binding;
    final available = b != null && b.usable && !b.busy;
    return Material(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 270),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b == null ? 'Open this page from an active Agent Hub selection.'
                : 'Selected agent: ${b.launch.agentId}', key: const Key('g6c-agent')),
            Text(b?.message ?? 'Zoom controls are unavailable without account and agent context.',
                key: const Key('g6c-connection-message')),
            const Text('Listening requires host approval and your consent. Nova remains muted.'),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton(key: const Key('g6c-refresh'),
                  onPressed: b != null && available ? () => unawaited(b.refresh()) : null,
                  child: const Text('Refresh status')),
              OutlinedButton(key: const Key('g6c-prepare'),
                  onPressed: b != null && available ? () => unawaited(b.prepareAuthorization()) : null,
                  child: const Text('Prepare Zoom authorization')),
              FilledButton(key: const Key('g6c-open'),
                  onPressed: b?.canOpenAuthorization == true
                      ? () => unawaited(b!.openAuthorization()) : null,
                  child: const Text('Open Zoom authorization')),
              OutlinedButton(key: const Key('g6c-meetings'),
                  onPressed: b != null && available && b.connected ? () => unawaited(b.loadMeetings()) : null,
                  child: const Text('List meetings')),
              OutlinedButton(key: const Key('g6c-disconnect'),
                  onPressed: b != null && available ? () => unawaited(b.disconnect()) : null,
                  child: const Text('Disconnect Zoom')),
            ]),
            if (b != null && b.meetings.isNotEmpty)
              ...b.meetings.map((m) => OutlinedButton(
                onPressed: available && !b.capture.busy && m.uuid != null
                    ? () => unawaited(b.capture.selectMeeting(m.uuid!)) : null,
                child: Text('${m.topic} — ${m.uuid == null ? "Meeting session unavailable" : "Select meeting"}'))),
            if (b != null) ...[
              Text(b.capture.statusLabel, key:const Key('g6n-session-status')),
              Text(b.capture.message, key:const Key('g6n-session-message')),
              if (b.capture.meetingUuid != null) Text('Meeting session: ${b.capture.meetingUuid}'),
              CheckboxListTile(key:const Key('g6n-consent'), contentPadding:EdgeInsets.zero,
                title:const Text('I consent to listening and transcription for this meeting.'),
                value:b.capture.consent,
                onChanged:b.capture.usable && !b.capture.busy && b.capture.meetingUuid != null
                    ? (v) => unawaited(b.capture.setConsent(v == true)) : null),
              OutlinedButton(key:const Key('g6n-refresh-session'),
                onPressed:b.capture.usable && !b.capture.busy ? () => unawaited(b.capture.refresh()) : null,
                child:const Text('Refresh session')),
              const Text('Use Stop before leaving. Closing or backgrounding stops consent renewal; remote capture ends when its permission expires.'),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // K135Z_B4B_V11_DIRECT_ROUTE_ENTERPRISE_GATE
    if (!kKorlixMeetingCopilotEnterpriseAccess.value) {
      return const KorlixMeetingCopilotLockedPage();
    }
    return Semantics(label: KorlixMeetingCopilotRoute.accessibilityLabel,
      child: KeyedSubtree(key: KorlixMeetingCopilotRoute.screenKey,
        child: Scaffold(body: SafeArea(child: Column(children: [
          _connectionPanel(),
          Expanded(child: KorlixMeetingCopilotScreen(
            controller: _controller,
            capture: _binding?.capture,
            workspaceController: widget.workspaceController,
            onConnectZoom: _binding?.usable == true && _binding?.busy == false
                ? () => unawaited(_binding!.prepareAuthorization()) : null,
            notesOnly: true,
            korlixLogo: const AssetImage(KorlixMeetingCopilotAssets.korlixLogo),
            novaPortrait: const AssetImage(KorlixMeetingCopilotAssets.novaPortrait),
          )),
        ]))),
      ),
    );
  }
}
