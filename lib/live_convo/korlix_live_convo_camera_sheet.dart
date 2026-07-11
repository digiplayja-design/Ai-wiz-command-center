import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as ip;

// KORLIX_LIVE_CONVO_CAMERA_SHEET_V1_BEGIN

typedef KorlixLiveConvoImageSender =
    Future<void> Function(Uint8List bytes, String mimeType, String instruction);

String? _korlixLiveConvoCameraMimeType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }

  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }

  return null;
}

Future<void> showKorlixLiveConvoCameraSheet({
  required BuildContext context,
  required bool currentlyMuted,
  required Future<void> Function()? onToggleMute,
  required KorlixLiveConvoImageSender onSendImage,
}) async {
  var temporarilyMuted = false;

  try {
    if (!currentlyMuted && onToggleMute != null) {
      await onToggleMute();
      temporarilyMuted = true;
    }

    final photo = await ip.ImagePicker().pickImage(
      source: ip.ImageSource.camera,
      requestFullMetadata: false,
      imageQuality: 28,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (photo == null) {
      return;
    }

    final bytes = await photo.readAsBytes();
    final mimeType = _korlixLiveConvoCameraMimeType(bytes);

    if (!context.mounted) {
      return;
    }

    if (mimeType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The camera picture was not JPEG or PNG. '
            'Please retake it.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The camera returned an empty picture.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (bytes.length > 110000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The picture is too large for LIVE CONVO. '
            'Please retake it and try again.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final instructionController = TextEditingController(
      text: 'What do you notice in this picture?',
    );

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: const Color(0xFF06131C),
        barrierColor: Colors.black.withValues(alpha: 0.72),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (sheetContext) {
          var sending = false;

          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Future<void> submitPicture() async {
                final instruction = instructionController.text.trim();

                if (sending || instruction.isEmpty) {
                  return;
                }

                setSheetState(() {
                  sending = true;
                });

                try {
                  await onSendImage(bytes, mimeType, instruction);

                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                } catch (error) {
                  if (!sheetContext.mounted) {
                    return;
                  }

                  setSheetState(() {
                    sending = false;
                  });

                  final message = error
                      .toString()
                      .replaceFirst('Bad state: ', '')
                      .replaceFirst('StateError: ', '');

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              }

              final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

              return Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.photo_camera_rounded,
                          color: Color(0xFFFFD166),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Show Korlix a Picture',
                            style: TextStyle(
                              color: Color(0xFFE4EBEE),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cancel picture',
                          onPressed: sending
                              ? null
                              : () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFFA9C6CF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 280),
                        color: Colors.black,
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: instructionController,
                      enabled: !sending,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        unawaited(submitPicture());
                      },
                      style: const TextStyle(
                        color: Color(0xFFE4EBEE),
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        labelText: 'What should Korlix analyze?',
                        labelStyle: const TextStyle(color: Color(0xFFFFD166)),
                        hintText: 'Ask about this picture…',
                        hintStyle: const TextStyle(color: Color(0xFF78909B)),
                        filled: true,
                        fillColor: const Color(0xFF020A10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: const BorderSide(
                            color: Color(0xFF5E522A),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: const BorderSide(
                            color: Color(0xFFFFD166),
                            width: 1.7,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: sending
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: sending
                                ? null
                                : () => unawaited(submitPicture()),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD166),
                              foregroundColor: const Color(0xFF081019),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            icon: sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                            label: Text(
                              sending ? 'Sending…' : 'Send Picture',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      instructionController.dispose();
    }
  } catch (error) {
    if (context.mounted) {
      final message = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('StateError: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Camera picture failed: $message'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  } finally {
    if (temporarilyMuted && onToggleMute != null && context.mounted) {
      try {
        await onToggleMute();
      } catch (_) {
        // Session cleanup handles this if the call ended.
      }
    }
  }
}

// KORLIX_LIVE_CONVO_CAMERA_SHEET_V1_END
