import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = ['Smooth', 'Gothic', 'Fiery', 'Mask', 'Smoky'];

    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Portrait History'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
          children: [
            const Text(
              'Saved Creations',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your improved portraits will appear here.',
              style: TextStyle(color: Colors.white.withOpacity(0.62)),
            ),
            const SizedBox(height: 18),
            ...items.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E17),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF7B3CFF).withOpacity(0.22),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 58,
                      width: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFF241A38),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.image_rounded,
                        color: Color(0xFFC07CFF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Icon(Icons.more_vert_rounded, color: Colors.white54),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
