import 'package:flutter/material.dart';

import 'korlix_live_convo_attachment.dart';

class KorlixLiveConvoAttachmentTray extends StatelessWidget {
  const KorlixLiveConvoAttachmentTray({
    super.key,
    required this.attachments,
    required this.onAddFiles,
    required this.onRemoveFile,
    required this.onClearFiles,
  });

  final List<KorlixLiveConvoAttachment> attachments;
  final Future<void> Function()? onAddFiles;
  final void Function(String attachmentId)? onRemoveFile;
  final VoidCallback? onClearFiles;

  IconData _iconFor(KorlixLiveConvoAttachment attachment) {
    if (attachment.mimeType.startsWith('image/')) {
      return Icons.image_rounded;
    }

    if (attachment.mimeType.contains('spreadsheet') ||
        attachment.mimeType.contains('excel') ||
        attachment.mimeType == 'text/csv') {
      return Icons.table_chart_rounded;
    }

    if (attachment.mimeType == 'application/pdf') {
      return Icons.picture_as_pdf_rounded;
    }

    return Icons.description_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2B7C8F), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.attach_file_rounded,
                color: Color(0xFF69D9E8),
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${attachments.length} LIVE DOCS '
                  '${attachments.length == 1 ? 'file' : 'files'} attached',
                  style: const TextStyle(
                    color: Color(0xFFE8F3F5),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: onAddFiles == null ? null : () => onAddFiles!(),
                child: const Text('Add files'),
              ),
              TextButton(
                onPressed: onClearFiles,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF7A8C),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < attachments.length; index += 1) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF020B12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF1C4350)),
              ),
              child: Row(
                children: [
                  Icon(
                    _iconFor(attachments[index]),
                    color: const Color(0xFF69D9E8),
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachments[index].displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE8F3F5),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${attachments[index].sizeLabel} • '
                          '${attachments[index].mimeType}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8FA9B3),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove ${attachments[index].displayName}',
                    onPressed: onRemoveFile == null
                        ? null
                        : () => onRemoveFile!(attachments[index].id),
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFFB8CBD1),
                  ),
                ],
              ),
            ),
            if (index < attachments.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 11),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFF62D6A7),
                size: 17,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'These files belong only to this LIVE CONVO session. '
                  'Ji-A can see their names now, but file contents are '
                  'not uploaded or readable until the secure document '
                  'extraction service is connected.',
                  style: TextStyle(
                    color: Color(0xFF9EB6BE),
                    fontSize: 11.5,
                    height: 1.38,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
