import 'package:ai_wiz_command_center/camera_ask/camera_capture_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

// Browser regression entry point. Runs the real capture route with an injected
// browser camera, without signing in, uploading a photo, or calling the API.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const MaterialApp(home: _Harness()));
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String _result = 'Ready';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_result),
          FilledButton(
            onPressed: () async {
              final photo = await captureCameraAskPhoto(context);
              if (!mounted) return;
              setState(() {
                _result = photo == null ? 'Camera closed' : 'Captured photo';
              });
            },
            child: const Text('Open camera'),
          ),
        ],
      ),
    ),
  );
}
