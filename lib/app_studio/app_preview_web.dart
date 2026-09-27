// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';

class AppPreview extends StatefulWidget {
  const AppPreview({super.key, required this.html});
  final String html;
  @override
  State<AppPreview> createState() => _AppPreviewState();
}

class _AppPreviewState extends State<AppPreview> {
  html.IFrameElement? _frame;
  @override
  void didUpdateWidget(AppPreview old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) _frame?.srcdoc = widget.html;
  }

  @override
  void dispose() {
    _frame?.srcdoc = '';
    _frame?.remove();
    _frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as html.IFrameElement;
      _frame = frame;
      frame.setAttribute('title', 'Interactive app preview');
      frame.setAttribute('sandbox', 'allow-scripts allow-forms');
      frame.setAttribute('referrerpolicy', 'no-referrer');
      frame.style
        ..width = '100%'
        ..height = '100%'
        ..border = '0'
        ..backgroundColor = '#f4f6fa';
      frame.srcdoc = widget.html;
    },
  );
}
