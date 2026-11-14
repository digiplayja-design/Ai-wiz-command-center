import 'package:flutter/material.dart';

import 'copybox_app.dart';
import 'copybox_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CopyBoxApp(auth: CopyBoxAuthController()));
}
