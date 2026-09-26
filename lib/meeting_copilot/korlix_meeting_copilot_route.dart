import 'k135z_startup_panel.dart';
import 'package:flutter/foundation.dart';
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
      final binding = _binding!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(binding, _binding)) unawaited(binding.initialize());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final binding = _binding;
      if (binding != null) {
        unawaited(binding.returnToPage());
        if (!binding.connected) unawaited(binding.initialize());
      }
    } else if (!(kIsWeb && state == AppLifecycleState.inactive)) {
      // Switching tabs/apps alone must not mute an enabled conversation.
      // Browser-imposed audio suspension uses the existing return/resume flow.
      _binding?.leavePage(keepVoiceActive: kIsWeb && state == AppLifecycleState.hidden);
    }
  }

  void _syncAccess() {
    final access = kKorlixMeetingCopilotEnterpriseAccess.value;
    widget.workspaceController?.setAccessGranted(access);
    if (!access) _binding?.invalidate();
    else if (_launch?.current == true && (_binding == null || !_binding!.usable)) _bind(_launch);
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


  @override
  Widget build(BuildContext context) {
    // K135Z_B4B_V11_DIRECT_ROUTE_ENTERPRISE_GATE
    if (!kKorlixMeetingCopilotEnterpriseAccess.value) {
      return const KorlixMeetingCopilotLockedPage();
    }
    return Semantics(label: KorlixMeetingCopilotRoute.accessibilityLabel,
      child: KeyedSubtree(key: KorlixMeetingCopilotRoute.screenKey,
        child: KorlixMeetingCopilotScreen(
            startupPanel: K135zStartupPanel(binding: _binding),
            controller: _controller,
            capture: _binding?.capture,
            meetingResponse: _binding?.response,
            workspaceController: widget.workspaceController,
            onConnectZoom: _binding?.usable == true && _binding?.busy == false
                ? () => _binding!.prepareAuthorization() : null,
            notesOnly: true,
            korlixLogo: const AssetImage(KorlixMeetingCopilotAssets.korlixLogo),
            novaPortrait: const AssetImage(KorlixMeetingCopilotAssets.novaPortrait),
          ),
      ),
    );
  }
}
