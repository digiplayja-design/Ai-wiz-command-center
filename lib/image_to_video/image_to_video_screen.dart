import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../privacy/korlix_third_party_ai_consent.dart';

typedef KorlixImageToVideoHeadersBuilder =
    Future<Map<String, String>> Function();

class KorlixImageToVideoScreen extends StatefulWidget {
  const KorlixImageToVideoScreen({
    super.key,
    required this.backendBaseUrl,
    this.headersBuilder,
  });

  final String backendBaseUrl;
  final KorlixImageToVideoHeadersBuilder? headersBuilder;

  @override
  State<KorlixImageToVideoScreen> createState() =>
      _KorlixImageToVideoScreenState();
}

class _KorlixImageToVideoScreenState extends State<KorlixImageToVideoScreen> {
  final TextEditingController _promptController = TextEditingController(
    text:
        'Animate this still image into a cinematic short video with natural motion, subtle camera movement, realistic lighting, and preserved identity.',
  );
  final TextEditingController _negativePromptController = TextEditingController(
    text:
        'warped face, flicker, extra limbs, distorted hands, blurry, low quality',
  );

  fp.PlatformFile? _imageFile;
  bool _loading = false;
  String _statusText = 'Upload an image, describe the motion, then generate.';
  String? _errorText;
  String? _jobId;
  String? _resultVideoUrl;
  String? _rawResponseText;

  String _duration = '5';
  String _aspectRatio = '9:16';
  String _motionStrength = 'medium';
  String _cameraMotion = 'cinematic drift';
  String _quality = 'high';

  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;

  Uint8List? get _imageBytes => _imageFile?.bytes;

  String get _endpointBase {
    final trimmed = widget.backendBaseUrl.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final supplied =
        await widget.headersBuilder?.call() ?? const <String, String>{};
    final headers = Map<String, String>.from(supplied);
    headers.removeWhere((key, _) => key.toLowerCase() == 'content-type');
    headers['Accept'] = 'application/json';
    return headers;
  }

  Future<void> _pickImage() async {
    final result = await fp.FilePicker.platform.pickFiles(
      type: fp.FileType.image,
      withData: true,
      allowMultiple: false,
    );

    final file = result?.files.single;
    if (file == null) {
      return;
    }

    if (file.bytes == null || file.bytes!.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorText = 'The selected image could not be read. Try another image.';
      });
      return;
    }

    setState(() {
      _imageFile = file;
      _errorText = null;
      _statusText = 'Image attached. Add motion details, then generate.';
      _resultVideoUrl = null;
      _jobId = null;
      _rawResponseText = null;
    });

    await _resetVideoController();
  }

  Future<void> _resetVideoController() async {
    final controller = _videoController;
    _videoController = null;
    _videoInitFuture = null;

    if (controller != null) {
      await controller.dispose();
    }
  }

  String? _stringAt(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _deepString(Map<String, dynamic> data, List<String> keys) {
    final direct = _stringAt(data, keys);
    if (direct != null) {
      return direct;
    }

    for (final value in data.values) {
      if (value is Map<String, dynamic>) {
        final nested = _deepString(value, keys);
        if (nested != null) {
          return nested;
        }
      } else if (value is List) {
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            final nested = _deepString(item, keys);
            if (nested != null) {
              return nested;
            }
          }
        }
      }
    }

    return null;
  }

  bool _isPlayableVideoUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _setVideoUrl(String? url) async {
    await _resetVideoController();

    if (url == null || url.trim().isEmpty) {
      return;
    }

    final cleaned = url.trim();
    _resultVideoUrl = cleaned;

    if (!_isPlayableVideoUrl(cleaned)) {
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(cleaned));
    _videoController = controller;
    _videoInitFuture = controller.initialize().then((_) {
      controller.setLooping(true);
      controller.play();

      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _generateVideo() async {
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_IMAGE_TO_VIDEO_BEGIN
    final korlixThirdPartyAiConsentGranted =
        await ensureKorlixThirdPartyAiConsent(
          context: context,
          featureName: 'Create Video',
          providers: const <KorlixThirdPartyAiProvider>{
            KorlixThirdPartyAiProvider.klingAi,
          },
          dataCategories: const <KorlixThirdPartyAiDataCategory>{
            KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            KorlixThirdPartyAiDataCategory.imagesAndPhotos,
          },
        );

    if (!korlixThirdPartyAiConsentGranted) {
      return;
    }
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_IMAGE_TO_VIDEO_END

    final file = _imageFile;
    final imageBytes = _imageBytes;
    final prompt = _promptController.text.trim();

    if (file == null || imageBytes == null || imageBytes.isEmpty) {
      setState(() {
        _errorText = 'Upload an image first.';
        _statusText = 'Image required.';
      });
      return;
    }

    if (prompt.isEmpty) {
      setState(() {
        _errorText = 'Describe the motion you want KORLIX AI to create.';
        _statusText = 'Motion prompt required.';
      });
      return;
    }

    await _resetVideoController();

    setState(() {
      _loading = true;
      _errorText = null;
      _jobId = null;
      _resultVideoUrl = null;
      _rawResponseText = null;
      _statusText = 'Uploading image and sending Image → Video job...';
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_endpointBase/api/video/image-to-video'),
      );

      request.headers.addAll(await _headers());
      request.fields.addAll({
        'prompt': prompt,
        'negativePrompt': _negativePromptController.text.trim(),
        'duration': _duration,
        'aspectRatio': _aspectRatio,
        'motionStrength': _motionStrength,
        'cameraMotion': _cameraMotion,
        'quality': _quality,
        'source': 'korlix_image_to_video_v1',
      });

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: file.name.isEmpty ? 'korlix-image-to-video.png' : file.name,
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final body = response.body;
      Map<String, dynamic> data = const <String, dynamic>{};

      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        // Keep raw body for the visible error.
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            _deepString(data, const ['error', 'message', 'details']) ??
            body.trim();

        setState(() {
          _loading = false;
          _errorText = message.isEmpty
              ? 'Image to Video failed with status ${response.statusCode}.'
              : message;
          _statusText = 'Generation failed.';
          _rawResponseText = body;
        });
        return;
      }

      final videoUrl = _deepString(data, const [
        'videoUrl',
        'video_url',
        'outputUrl',
        'output_url',
        'url',
        'downloadUrl',
        'download_url',
        'fileUrl',
        'file_url',
      ]);

      final jobId = _deepString(data, const [
        'jobId',
        'job_id',
        'id',
        'taskId',
        'task_id',
      ]);

      setState(() {
        _jobId = jobId;
        _rawResponseText = const JsonEncoder.withIndent('  ').convert(data);
        _statusText = videoUrl != null
            ? 'Video ready.'
            : jobId != null
            ? 'Video job started. Waiting for completion...'
            : 'Job submitted. Waiting for video URL.';
      });

      if (videoUrl != null) {
        await _setVideoUrl(videoUrl);

        if (mounted) {
          setState(() {
            _loading = false;
            _statusText = 'Video ready.';
          });
        }
        return;
      }

      if (jobId != null) {
        await _pollJob(jobId);
        return;
      }

      setState(() {
        _loading = false;
        _errorText =
            'The provider accepted the request but did not return a video URL or job ID.';
        _statusText = 'Generation incomplete.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorText = 'Image to Video failed: $error';
        _statusText = 'Generation failed.';
      });
    }
  }

  Future<void> _pollJob(String jobId) async {
    for (var attempt = 1; attempt <= 75; attempt++) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusText = 'Generating video... status check $attempt/75';
      });

      await Future<void>.delayed(const Duration(seconds: 4));

      try {
        final response = await http.get(
          Uri.parse('$_endpointBase/api/video/image-to-video/status/$jobId'),
          headers: await _headers(),
        );

        Map<String, dynamic> data = const <String, dynamic>{};
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {}

        final status =
            _deepString(data, const [
              'status',
              'state',
              'phase',
            ])?.toLowerCase() ??
            '';

        final videoUrl = _deepString(data, const [
          'videoUrl',
          'video_url',
          'outputUrl',
          'output_url',
          'url',
          'downloadUrl',
          'download_url',
          'fileUrl',
          'file_url',
        ]);

        if (videoUrl != null) {
          await _setVideoUrl(videoUrl);

          if (mounted) {
            setState(() {
              _loading = false;
              _statusText = 'Video ready.';
              _rawResponseText = const JsonEncoder.withIndent(
                '  ',
              ).convert(data);
            });
          }
          return;
        }

        if (status == 'failed' ||
            status == 'error' ||
            status == 'cancelled' ||
            status == 'canceled') {
          final message =
              _deepString(data, const ['error', 'message', 'details']) ??
              'Image to Video job failed.';

          if (mounted) {
            setState(() {
              _loading = false;
              _errorText = message;
              _statusText = 'Generation failed.';
              _rawResponseText = const JsonEncoder.withIndent(
                '  ',
              ).convert(data);
            });
          }
          return;
        }

        if (mounted) {
          setState(() {
            _rawResponseText = const JsonEncoder.withIndent('  ').convert(data);
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _rawResponseText = 'Polling error: $error';
          });
        }
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _errorText =
          'Video generation is still processing. Try again later or check provider dashboard.';
      _statusText = 'Still processing.';
    });
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(
      ClipboardData(
        text:
            'Image to Video prompt:\n${_promptController.text.trim()}\n\nNegative prompt:\n${_negativePromptController.text.trim()}\nDuration: $_duration\nAspect ratio: $_aspectRatio\nMotion strength: $_motionStrength\nCamera motion: $_cameraMotion\nQuality: $_quality',
      ),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Image to Video prompt copied.')),
    );
  }

  Future<void> _copyVideoUrl() async {
    final url = _resultVideoUrl;
    if (url == null || url.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: url));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Video URL copied.')));
  }

  Future<void> _openVideoUrl() async {
    final url = _resultVideoUrl;
    if (url == null || url.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareVideoUrl() async {
    final url = _resultVideoUrl;
    if (url == null || url.isEmpty) {
      return;
    }

    await Share.share('KORLIX AI Image to Video result:\n$url');
  }

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      selected: active,
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF7C3DFF),
      backgroundColor: const Color(0xFF101928),
      labelStyle: TextStyle(
        color: active ? Colors.white : const Color(0xFFB9C7D9),
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(
        color: active
            ? const Color(0xFFD66BFF)
            : Colors.white.withValues(alpha: 0.16),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF69D9E8).withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3DFF).withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildUploadCard() {
    final bytes = _imageBytes;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image_outlined, color: Color(0xFF69D9E8)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Source Image',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _pickImage,
                icon: const Icon(Icons.upload_rounded),
                label: Text(bytes == null ? 'Upload' : 'Replace'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (bytes == null)
            InkWell(
              onTap: _loading ? null : _pickImage,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 220,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF69D9E8).withValues(alpha: 0.38),
                  ),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_rounded,
                      color: Color(0xFF69D9E8),
                      size: 42,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Tap to upload the still image',
                      style: TextStyle(
                        color: Color(0xFFE4EBEE),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'JPG, PNG, or WEBP',
                      style: TextStyle(color: Color(0xFFA9C6CF)),
                    ),
                  ],
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.memory(
                bytes,
                width: double.infinity,
                height: 260,
                fit: BoxFit.cover,
              ),
            ),
          if (_imageFile != null) ...[
            const SizedBox(height: 8),
            Text(
              _imageFile!.name,
              style: const TextStyle(
                color: Color(0xFFA9C6CF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPromptCard() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Motion Prompt',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promptController,
            minLines: 4,
            maxLines: 8,
            enabled: !_loading,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Describe how the image should move...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.46)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF69D9E8),
                  width: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Negative Prompt',
            style: TextStyle(
              color: Color(0xFFB9C7D9),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _negativePromptController,
            minLines: 2,
            maxLines: 4,
            enabled: !_loading,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'What should the video avoid?',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.46)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _copyPrompt,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Prompt'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Video Controls',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Duration', style: TextStyle(color: Color(0xFFA9C6CF))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const ['5', '8', '10'])
                _chip(
                  label: '${value}s',
                  active: _duration == value,
                  onTap: () => setState(() => _duration = value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Aspect Ratio',
            style: TextStyle(color: Color(0xFFA9C6CF)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const ['9:16', '1:1', '16:9', '4:5'])
                _chip(
                  label: value,
                  active: _aspectRatio == value,
                  onTap: () => setState(() => _aspectRatio = value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Motion Strength',
            style: TextStyle(color: Color(0xFFA9C6CF)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const ['low', 'medium', 'high'])
                _chip(
                  label: value,
                  active: _motionStrength == value,
                  onTap: () => setState(() => _motionStrength = value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Camera Motion',
            style: TextStyle(color: Color(0xFFA9C6CF)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const [
                'none',
                'zoom in',
                'zoom out',
                'pan left',
                'pan right',
                'cinematic drift',
              ])
                _chip(
                  label: value,
                  active: _cameraMotion == value,
                  onTap: () => setState(() => _cameraMotion = value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Quality', style: TextStyle(color: Color(0xFFA9C6CF))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const ['standard', 'high'])
                _chip(
                  label: value,
                  active: _quality == value,
                  onTap: () => setState(() => _quality = value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final videoUrl = _resultVideoUrl;
    final controller = _videoController;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Output',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _statusText,
            style: const TextStyle(
              color: Color(0xFFA9C6CF),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorText!,
              style: const TextStyle(
                color: Color(0xFFFF6B6B),
                fontWeight: FontWeight.w900,
                height: 1.35,
              ),
            ),
          ],
          if (_jobId != null) ...[
            const SizedBox(height: 10),
            Text(
              'Job ID: $_jobId',
              style: const TextStyle(
                color: Color(0xFF69D9E8),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (videoUrl != null) ...[
            const SizedBox(height: 14),
            if (controller != null && _videoInitFuture != null)
              FutureBuilder<void>(
                future: _videoInitFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Container(
                      height: 220,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const CircularProgressIndicator(),
                    );
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio == 0
                          ? 9 / 16
                          : controller.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(controller),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: FloatingActionButton.small(
                              heroTag: 'korlix_image_to_video_play',
                              onPressed: () {
                                setState(() {
                                  controller.value.isPlaying
                                      ? controller.pause()
                                      : controller.play();
                                });
                              },
                              child: Icon(
                                controller.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              )
            else
              SelectableText(
                videoUrl,
                style: const TextStyle(
                  color: Color(0xFF69D9E8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _openVideoUrl,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download / Open'),
                ),
                OutlinedButton.icon(
                  onPressed: _copyVideoUrl,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy URL'),
                ),
                OutlinedButton.icon(
                  onPressed: _shareVideoUrl,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
          if (_rawResponseText != null) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              iconColor: const Color(0xFF69D9E8),
              collapsedIconColor: const Color(0xFFA9C6CF),
              title: const Text(
                'Provider response',
                style: TextStyle(
                  color: Color(0xFFA9C6CF),
                  fontWeight: FontWeight.w800,
                ),
              ),
              children: [
                SelectableText(
                  _rawResponseText!,
                  style: const TextStyle(
                    color: Color(0xFFB9C7D9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGenerate =
        !_loading &&
        _imageBytes != null &&
        _promptController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF040711),
      appBar: AppBar(
        backgroundColor: const Color(0xFF040711),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Image to Video',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF120726),
                    Color(0xFF07111F),
                    Color(0xFF061E2B),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFD66BFF).withValues(alpha: 0.32),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.movie_creation_outlined,
                        color: Color(0xFFD66BFF),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Turn a still image into a cinematic moving clip.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Upload one image, describe the motion, choose video settings, and KORLIX AI will send it to the configured image-to-video provider.',
                    style: TextStyle(
                      color: Color(0xFFA9C6CF),
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildUploadCard(),
            const SizedBox(height: 14),
            _buildPromptCard(),
            const SizedBox(height: 14),
            _buildControlsCard(),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: canGenerate ? _generateVideo : null,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_motion_rounded),
              label: Text(
                _loading ? 'Generating Video...' : 'Generate Image to Video',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3DFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildResultCard(),
          ],
        ),
      ),
    );
  }
}
