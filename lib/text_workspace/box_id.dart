import 'dart:math';

String boxId() =>
    // A bit shift by 32 becomes zero in JavaScript. Use the numeric bound so
    // creating a box works in Flutter web as well as on native devices.
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x100000000)}';
