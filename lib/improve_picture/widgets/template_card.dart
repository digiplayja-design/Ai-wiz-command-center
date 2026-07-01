import 'package:flutter/material.dart';

import '../models/template_model.dart';

class TemplateCard extends StatelessWidget {
  const TemplateCard({super.key, required this.template, required this.onTap});

  final ImproveTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0E17),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF7B3CFF).withOpacity(0.28),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '✦ 3 looks',
                style: TextStyle(
                  color: Color(0xFFC07CFF),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Icon(template.icon, color: Colors.white, size: 42),
              const SizedBox(height: 12),
              Text(
                template.name.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                template.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
