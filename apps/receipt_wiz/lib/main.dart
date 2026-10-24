import 'package:flutter/material.dart';

import 'receipt_app.dart';
import 'receipt_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ReceiptWizApp(auth: ReceiptAuthController()));
}
