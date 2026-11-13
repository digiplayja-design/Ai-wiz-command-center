import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String projectionLayoutPreference(Object? value) =>
    value == 'landscape' || value == 'portrait' ? value as String : 'auto';

bool projectionUsesLandscape(String preference, Size window) =>
    preference == 'landscape' ||
    (preference == 'auto' && window.width > window.height);

Map<String, dynamic> projectionNativeViewport({
  required Size window,
  required Size viewport,
  required String preference,
}) => {
  'width': viewport.width,
  'height': viewport.height,
  // A narrow keyboard/multitasking remainder needs the stacked controls.
  // Native phone landscape can be narrower than the web preview's 600 px
  // breakpoint; 480 px still accommodates the compact scene and console.
  'landscape': projectionUsesLandscape(preference, window) && viewport.width >= 480,
};

/// Requests native orientation without letting a late close restore over a
/// newly opened Projection. The empty list restores the OS's normal policy.
class BrainProjectionOrientation {
  BrainProjectionOrientation({
    Future<void> Function(List<DeviceOrientation>)? setOrientations,
  }) : _setOrientations =
           setOrientations ?? SystemChrome.setPreferredOrientations,
       _owner = ++_latestOwner;

  static int _latestOwner = 0;
  static Future<void> _queue = Future<void>.value();
  final int _owner;
  final Future<void> Function(List<DeviceOrientation>) _setOrientations;
  String? _preference;
  bool _disposed = false;

  Future<void> update(String value) {
    final preference = projectionLayoutPreference(value);
    if (_disposed || _preference == preference) return _queue;
    _preference = preference;
    return _schedule(() async {
      if (_disposed || _owner != _latestOwner || preference != _preference) {
        return;
      }
      await _setOrientations(switch (preference) {
        'landscape' => const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        'portrait' => const [DeviceOrientation.portraitUp],
        _ => const <DeviceOrientation>[],
      });
    });
  }

  Future<void> restore() {
    if (_disposed) return _queue;
    _disposed = true;
    return _schedule(() async {
      if (_owner == _latestOwner) {
        await _setOrientations(const <DeviceOrientation>[]);
      }
    });
  }

  static Future<void> _schedule(Future<void> Function() action) {
    // Platform refusal must not break native controls or produce an unhandled
    // future. The presentation also handles windows whose OS cannot rotate.
    _queue = _queue.then((_) => action()).catchError((Object _) {});
    return _queue;
  }
}

/// Native controls are outside the platform view, so page loading, a failed
/// renderer, scrolling and the software keyboard cannot hide the stop action.
/// A fixed RotatedBox keeps the same child mounted when explicit orientation
/// is requested in a window the OS does not rotate (for example iPad Split View).
class BrainProjectionPresentation extends StatelessWidget {
  const BrainProjectionPresentation({
    super.key,
    required this.child,
    required this.voice,
    required this.layoutPreference,
    required this.onClose,
    required this.onVoiceAction,
    required this.onLayout,
    this.voiceAction = '',
  });

  final Widget child;
  final Map<String, dynamic> voice;
  final String layoutPreference;
  final String voiceAction;
  final VoidCallback onClose;
  final ValueChanged<String> onVoiceAction;
  final ValueChanged<String> onLayout;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    final landscapeWindow = window.width > window.height;
    return LayoutBuilder(builder: (context, constraints) {
      // A keyboard may make the remaining portrait area short. Keep the rail
      // in that available area instead of rotating it into an unusably narrow
      // strip. The preferred native orientation remains in effect.
      final turns = layoutPreference == 'landscape' && !landscapeWindow &&
              constraints.maxHeight > constraints.maxWidth
          ? 1
          : layoutPreference == 'portrait' && landscapeWindow &&
              constraints.maxHeight >= 280
          ? 3
          : 0;
      return RotatedBox(
      key: const ValueKey('projection-presentation'),
      quarterTurns: turns,
      child: Column(
        children: [
          Expanded(child: child),
          _ProjectionControls(
            voice: voice,
            voiceAction: voiceAction,
            layoutPreference: layoutPreference,
            onClose: onClose,
            onVoiceAction: onVoiceAction,
            onLayout: onLayout,
          ),
        ],
      ),
      );
    });
  }
}

class _ProjectionControls extends StatelessWidget {
  const _ProjectionControls({
    required this.voice,
    required this.voiceAction,
    required this.layoutPreference,
    required this.onClose,
    required this.onVoiceAction,
    required this.onLayout,
  });

  final Map<String, dynamic> voice;
  final String voiceAction;
  final String layoutPreference;
  final VoidCallback onClose;
  final ValueChanged<String> onVoiceAction;
  final ValueChanged<String> onLayout;

  Widget _button(String action, String label, IconData icon,
      VoidCallback? callback, {bool stop = false}) {
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? const Color(0xff9c93ac)
              : stop ? const Color(0xffffd8dd) : const Color(0xffe4e2f5)),
      backgroundColor: WidgetStatePropertyAll(
          stop ? const Color(0xff4b2237) : const Color(0xff222238)),
    );
    return Tooltip(
      message: action == 'back' ? 'Back to your conversation' : '$label conversation',
      child: SizedBox(
        height: 48,
        child: OutlinedButton(
          key: ValueKey('projection-native-$action'),
          onPressed: callback,
          style: style,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, height: 1.1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layoutChoice(String preference, String label, double width) =>
      Semantics(
        selected: layoutPreference == preference,
        child: SizedBox(
          width: width,
          height: 48,
          child: TextButton(
            key: ValueKey('projection-native-layout-$preference'),
            onPressed: () => onLayout(preference),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              backgroundColor: layoutPreference == preference
                  ? const Color(0xff35536a) : const Color(0xff171727),
              foregroundColor: const Color(0xffe4eef7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final active = voice['active'] == true;
    final paused = voice['paused'] == true || voice['phase'] == 'paused';
    final phase = voiceAction == 'stop' ? 'stopping'
        : voiceAction == 'pause' ? 'pausing'
        : (voiceAction == 'start' || voiceAction == 'resume') && !active
        ? 'connecting' : voice['phase'] ?? 'complete';
    final session = active || paused || voiceAction.isNotEmpty ||
        !const {'complete', 'error'}.contains(phase);
    final canPause = !const {'pausing', 'stopping'}.contains(phase) &&
        (active || phase == 'connecting');
    final canResume = paused && phase == 'paused' && voiceAction.isEmpty;
    final canStop = session && voiceAction != 'stop';
    final phaseLabel = switch (phase) {
      'paused' => 'Paused · mic off',
      'pausing' => 'Pausing…',
      'stopping' => 'Stopping…',
      'connecting' => 'Connecting…',
      'listening' => 'Rici is listening',
      'thinking' => 'Rici is thinking',
      'speaking' => 'Rici is speaking',
      _ => 'Microphone off',
    };
    final status = Semantics(
      liveRegion: true,
      child: Text(
        layoutPreference == 'portrait' ? '$phaseLabel · Portrait' : phaseLabel,
        key: const ValueKey('projection-native-voice-state'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xffd4cede), fontSize: 11),
      ),
    );
    final back = _button('back', 'Back', Icons.arrow_back, onClose);
    final choices = Row(mainAxisSize: MainAxisSize.min, children: [
      _layoutChoice('auto', 'Auto', 44),
      const SizedBox(width: 4),
      _layoutChoice('landscape', 'Landscape', 78),
    ]);
    final actions = [
      _button('start', 'Talk', Icons.mic_none,
          !session ? () => onVoiceAction('start') : null),
      _button('pause', 'Pause', Icons.pause,
          canPause ? () => onVoiceAction('pause') : null),
      _button('resume', 'Resume', Icons.play_arrow,
          canResume ? () => onVoiceAction('resume') : null),
      _button('stop', 'Stop', Icons.stop,
          canStop ? () => onVoiceAction('stop') : null, stop: true),
    ];
    return Material(
      key: const ValueKey('projection-native-controls'),
      color: const Color(0xff151525),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= 540) {
            return Row(children: [
              SizedBox(width: 54, child: back),
              const SizedBox(width: 8),
              Expanded(child: status),
              const SizedBox(width: 6),
              choices,
              for (final action in actions) ...[
                const SizedBox(width: 4),
                SizedBox(width: 54, child: action),
              ],
            ]);
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              SizedBox(width: 54, child: back),
              const SizedBox(width: 8),
              Expanded(child: status),
              const SizedBox(width: 6),
              choices,
            ]),
            const SizedBox(height: 6),
            Row(children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(width: 6),
                Expanded(child: actions[index]),
              ],
            ]),
          ]);
        }),
      ),
    );
  }
}
