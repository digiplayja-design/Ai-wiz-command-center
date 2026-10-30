import 'package:flutter/material.dart';

import 'magic_app.dart';
import 'magic_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MagicCameraApp(auth: MagicAuthController()));
}
