import 'package:flutter/material.dart';

import 'brain_app.dart';
import 'brain_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(BrainApp(auth: BrainAuthController()));
}
