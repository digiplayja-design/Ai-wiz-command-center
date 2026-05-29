import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const CheeChaiCheeApp());
}

String backendUrl() {
  const overrideUrl = String.fromEnvironment('AI_WIZARD_BACKEND_URL');

  if (overrideUrl.isNotEmpty) {
    if (overrideUrl.endsWith('/api/generate')) {
      return overrideUrl;
    }
    return '$overrideUrl/api/generate';
  }

  final host = Uri.base.host;

  if (host.contains('-3000.app.github.dev')) {
    final backendHost = host.replaceFirst(
      '-3000.app.github.dev',
      '-8787.app.github.dev',
    );
    return 'https://$backendHost/api/generate';
  }

  return 'http://localhost:8787/api/generate';
}

class CheeChaiCheeApp extends StatelessWidget {
  const CheeChaiCheeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chee Chai Chee',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const CommandCenterScreen(),
    );
  }
}

class GeneratedFile {
  final String command;
  final String fileName;
  final String content;

  const GeneratedFile({
    required this.command,
    required this.fileName,
    required this.content,
  });
}

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({super.key});

  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  final TextEditingController _controller = TextEditingController();

  bool _loading = false;
  String? _error;
  final List<GeneratedFile> _files = [];

  final List<String> _ideas = const [
    'Make me a business plan',
    'Create a study guide',
    'Write a resume',
    'Make a workout plan',
    'Create a meal plan',
    'Write a social media post',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final command = _controller.text.trim();

    if (command.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a command first.')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(backendUrl()),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'command': command}),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(response.body);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (data['content'] ?? '').toString().trim();

      if (content.isEmpty) {
        throw Exception('No AI content returned.');
      }

      setState(() {
        _loading = false;
        _controller.clear();
        _files.insert(
          0,
          GeneratedFile(
            command: command,
            fileName: _makeFileName(command),
            content: content,
          ),
        );
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = 'Creation failed. Make sure the backend is running.';
      });
    }
  }

  String _makeFileName(String text) {
    final words = RegExp(r'[A-Za-z0-9]+')
        .allMatches(text)
        .map((match) => match.group(0)!)
        .take(5)
        .toList();

    if (words.isEmpty) {
      return 'Chee_Chai_Chee_Output.pdf';
    }

    return '${words.join('_')}.pdf';
  }

  String _cleanMarkdown(String text) {
    return text
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
        .trim();
  }

  List<pw.Widget> _pdfContentWidgets(String content) {
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final widgets = <pw.Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
        continue;
      }

      if (trimmed.startsWith('###')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
            child: pw.Text(
              _cleanMarkdown(trimmed),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('##')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
            child: pw.Text(
              _cleanMarkdown(trimmed),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('- ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 10, bottom: 4),
            child: pw.Text(
              '• ${_cleanMarkdown(trimmed.substring(2))}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        );
      } else {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(
              _cleanMarkdown(trimmed),
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Future<Uint8List> _buildPdf(GeneratedFile file) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return [
            pw.Text(
              file.fileName.replaceAll('_', ' ').replaceAll('.pdf', ''),
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Generated by Chee Chai Chee',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Original command: ${file.command}',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 14),
            ..._pdfContentWidgets(file.content),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _exportPdf(GeneratedFile file) async {
    try {
      final bytes = await _buildPdf(file);

      await Printing.sharePdf(
        bytes: bytes,
        filename: file.fileName,
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF export failed. Try again.'),
        ),
      );
    }
  }

  void _showFile(GeneratedFile file) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(file.fileName),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: SelectableText(file.content),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _exportPdf(file),
              child: const Text('Export PDF'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF040612),
              Color(0xFF10173A),
              Color(0xFF250032),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                child: Column(
                  children: [
                    const Text(
                      'CHEE CHAI CHEE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The living AI wizard that turns commands into finished files.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.35),
                        ),
                      ),
                      child: const Text(
                        'Backend connected',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const TalkingWizardHost(),
                    const SizedBox(height: 28),
                    _buildCommandPanel(),
                    const SizedBox(height: 26),
                    _buildGeneratedFiles(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommandPanel() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.10),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'What shall we create?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Type your command here...',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.black.withOpacity(0.35),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: _ideas.map((idea) {
              return ActionChip(
                label: Text(idea),
                onPressed: _loading
                    ? null
                    : () {
                        setState(() {
                          _controller.text = idea;
                        });
                      },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _generate,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _loading ? 'Creating with Chee Chai Chee...' : 'Create Deliverable',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            backendUrl(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white30,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedFiles() {
    if (_files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Generated Files',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ..._files.map((file) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.picture_as_pdf,
                  color: Colors.redAccent,
                  size: 34,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.fileName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        file.command,
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        file.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => _showFile(file),
                      child: const Text('Open'),
                    ),
                    OutlinedButton(
                      onPressed: () => _exportPdf(file),
                      child: const Text('PDF'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}









class TalkingWizardHost extends StatefulWidget {
  const TalkingWizardHost({super.key});

  @override
  State<TalkingWizardHost> createState() => _TalkingWizardHostState();
}

class _WizardLanguage {
  final String code;
  final String label;
  final String assetPath;
  final String awakenText;

  const _WizardLanguage({
    required this.code,
    required this.label,
    required this.assetPath,
    required this.awakenText,
  });
}

class _TalkingWizardHostState extends State<TalkingWizardHost> {
  VideoPlayerController? _controller;

  bool _loading = true;
  bool _started = false;
  bool _needsTap = false;
  String? _error;

  String _selectedLanguage = 'en';

  static const List<_WizardLanguage> _languages = [
    _WizardLanguage(
      code: 'en',
      label: 'English',
      assetPath: 'assets/wizard_greeting_en.mp4',
      awakenText: 'Awaken Chee Chai Chee',
    ),
    _WizardLanguage(
      code: 'es',
      label: 'Español',
      assetPath: 'assets/wizard_greeting_es.mp4',
      awakenText: 'Despertar a Chee Chai Chee',
    ),
    _WizardLanguage(
      code: 'fr',
      label: 'Français',
      assetPath: 'assets/wizard_greeting_fr.mp4',
      awakenText: 'Réveiller Chee Chai Chee',
    ),
  ];

  _WizardLanguage get _currentLanguage {
    return _languages.firstWhere(
      (item) => item.code == _selectedLanguage,
      orElse: () => _languages.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadWizardVideo();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadWizardVideo() async {
    setState(() {
      _loading = true;
      _started = false;
      _needsTap = false;
      _error = null;
    });

    try {
      final oldController = _controller;
      _controller = null;
      await oldController?.dispose();

      final controller = VideoPlayerController.asset(
        _currentLanguage.assetPath,
      );

      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1.0);
      await controller.seekTo(Duration.zero);

      if (!mounted) return;

      setState(() {
        _controller = controller;
        _loading = false;
        _started = false;
        _needsTap = true;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _started = false;
        _needsTap = false;
        _error = 'Chee Chai Chee could not load this language. Tap retry.';
      });
    }
  }

  Future<void> _changeLanguage(String code) async {
    if (code == _selectedLanguage) {
      return;
    }

    setState(() {
      _selectedLanguage = code;
    });

    await _loadWizardVideo();
  }

  void _playWizard() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      setState(() {
        _started = false;
        _needsTap = true;
      });
      return;
    }

    setState(() {
      _started = true;
      _needsTap = false;
      _error = null;
    });

    // Keep this direct and simple so iPad/Safari treats it as a real tap action.
    controller.setVolume(1.0);
    controller.seekTo(Duration.zero);

    controller.play().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;

        final currentController = _controller;

        if (currentController != null && !currentController.value.isPlaying) {
          setState(() {
            _started = false;
            _needsTap = true;
          });
        }
      });
    }).catchError((_) {
      if (!mounted) return;

      setState(() {
        _started = false;
        _needsTap = true;
      });
    });
  }

  void _replayWizard() {
    _playWizard();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.30),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.25),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: _languages.map((language) {
              final selected = language.code == _selectedLanguage;

              return ChoiceChip(
                selected: selected,
                label: Text(language.label),
                onSelected: _loading
                    ? null
                    : (_) {
                        _changeLanguage(language.code);
                      },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: 365,
          constraints: const BoxConstraints(maxWidth: 365),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.26),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.24),
                blurRadius: 58,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: Colors.purpleAccent.withOpacity(0.24),
                blurRadius: 90,
                spreadRadius: 16,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Color(0xFF10173A),
                          Color(0xFF050816),
                          Color(0xFF02030A),
                        ],
                        radius: 1.1,
                      ),
                    ),
                  ),

                  if (controller != null && controller.value.isInitialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.size.width,
                        height: controller.value.size.height,
                        child: VideoPlayer(controller),
                      ),
                    ),

                  if (_loading)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text('Preparing ${_currentLanguage.label}...'),
                        ],
                      ),
                    ),

                  if (!_loading && !_started && _needsTap && _error == null)
                    Container(
                      color: Colors.black.withOpacity(0.52),
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.all(28),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.76),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.cyanAccent.withOpacity(0.35),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: Colors.cyanAccent,
                                size: 42,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Chee Chai Chee awaits.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _currentLanguage.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _playWizard,
                                icon: const Icon(Icons.play_arrow),
                                label: Text(_currentLanguage.awakenText),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loadWizardVideo,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          children: [
            FilledButton.icon(
              onPressed: controller == null ? null : _replayWizard,
              icon: const Icon(Icons.replay),
              label: const Text('Replay Greeting'),
            ),
            OutlinedButton.icon(
              onPressed: _loadWizardVideo,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload Wizard'),
            ),
          ],
        ),
      ],
    );
  }
}
