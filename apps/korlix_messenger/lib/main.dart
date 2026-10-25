import 'package:korlix_social_core/social/social_bubble_app.dart';
import 'package:flutter/material.dart';

import 'messenger_app.dart';
import 'messenger_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KorlixMessengerApp(auth: MessengerAuthController()));
}

@pragma('vm:entry-point')
void socialBubbleMain() => runSocialBubble(messengerMode: true);
