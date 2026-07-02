import 'dart:async';

import 'package:file_picker/file_picker.dart' as fp;

typedef KorlixPreviewHeadersBuilder = FutureOr<Map<String, String>> Function();

typedef ImprovePicturePromptCallback =
    void Function(String prompt, fp.PlatformFile? imageFile, bool autoSubmit);
