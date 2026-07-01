import 'package:flutter/material.dart';

import '../models/template_model.dart';
import 'history_screen.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.gender,
    required this.template,
    required this.variation,
    required this.strength,
    required this.ratio,
    required this.hasUploadedPhoto,
  });

  final ImproveGender gender;
  final ImproveTemplate template;
  final String variation;
  final double strength;
  final String ratio;
  final bool hasUploadedPhoto;

  @override
  Widget build(BuildContext context) {
    final percent = (strength * 100).round();

    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Result Saved'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
          children: [
            Container(
              height: 430,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E17),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFF7B3CFF).withOpacity(0.30),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      template.icon,
                      color: const Color(0xFFC07CFF),
                      size: 120,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      template.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      variation,
                      style: const TextStyle(
                        color: Color(0xFFC07CFF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'HD result placeholder',
                      style: TextStyle(color: Colors.white.withOpacity(0.58)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _resultBox(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Final Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(label: 'Template', value: template.name),
                  _InfoRow(label: 'Variation', value: variation),
                  _InfoRow(label: 'Strength', value: '$percent%'),
                  _InfoRow(label: 'Ratio', value: ratio),
                  _InfoRow(
                    label: 'Photo',
                    value: hasUploadedPhoto ? 'Uploaded' : 'Demo',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.65,
              children: [
                _ActionTile(
                  icon: Icons.download_rounded,
                  label: 'Save',
                  onTap: () {},
                ),
                _ActionTile(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  onTap: () {},
                ),
                _ActionTile(
                  icon: Icons.favorite_border_rounded,
                  label: 'Favorite',
                  onTap: () {},
                ),
                _ActionTile(
                  icon: Icons.edit_rounded,
                  label: 'Edit Again',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
                icon: const Icon(Icons.history_rounded),
                label: const Text(
                  'View History',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B3DFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.55)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _resultBox() {
  return BoxDecoration(
    color: const Color(0xFF0B0E17),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: const Color(0xFF7B3CFF).withOpacity(0.26)),
  );
}
