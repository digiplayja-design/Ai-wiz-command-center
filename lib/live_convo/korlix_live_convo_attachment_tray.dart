import 'package:flutter/material.dart';

import 'korlix_live_convo_attachment.dart';
import 'korlix_live_convo_file_submission.dart';

class KorlixLiveConvoAttachmentTray extends StatelessWidget {
  const KorlixLiveConvoAttachmentTray({
    super.key,
    required this.attachments,
    required this.submissionState,
    required this.onAddFiles,
    required this.onRemoveFile,
    required this.onClearFiles,
    required this.onSubmitFiles,
    this.submissionError,
  });

  final List<KorlixLiveConvoAttachment> attachments;

  final KorlixLiveConvoFileSubmissionState submissionState;
  final String? submissionError;

  final Future<void> Function()? onAddFiles;
  final void Function(String attachmentId)? onRemoveFile;
  final VoidCallback? onClearFiles;
  final Future<void> Function()? onSubmitFiles;

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

  Color get _statusColor {
    switch (submissionState) {
      case KorlixLiveConvoFileSubmissionState.localOnly:
        return const Color(0xFFFFD166);

      case KorlixLiveConvoFileSubmissionState.submitting:
        return const Color(0xFF69D9E8);

      case KorlixLiveConvoFileSubmissionState.ready:
        return const Color(0xFF62D6A7);

      case KorlixLiveConvoFileSubmissionState.failed:
        return const Color(0xFFFF7A8C);
    }
  }

  String get _disclosureText {
    switch (submissionState) {
      case KorlixLiveConvoFileSubmissionState.localOnly:
        return 'These files are currently stored on this device only. '
            'Tap Send Files to Ji-A to upload and process their contents.';

      case KorlixLiveConvoFileSubmissionState.submitting:
        return 'The selected files are being uploaded to Korlix’s '
            'authenticated analysis service and processed for this '
            'LIVE CONVO session.';

      case KorlixLiveConvoFileSubmissionState.ready:
        return 'The processed source dossier is now available to Ji-A '
            'inside this LIVE CONVO session.';

      case KorlixLiveConvoFileSubmissionState.failed:
        return 'The files remain attached locally, but processing did '
            'not complete. Review the error and retry.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }

    final submitting = submissionState.isSubmitting;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: submissionState.isReady
              ? const Color(0xFF2C9A73)
              : const Color(0xFF2B7C8F),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                submissionState.isReady
                    ? Icons.verified_rounded
                    : Icons.attach_file_rounded,
                color: _statusColor,
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
                onPressed: submitting || onAddFiles == null
                    ? null
                    : () => onAddFiles!(),
                child: const Text('Add files'),
              ),
              TextButton(
                onPressed: submitting ? null : onClearFiles,
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
                border: Border.all(
                  color: submissionState.isReady
                      ? const Color(0xFF245E4D)
                      : const Color(0xFF1C4350),
                ),
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
                        const SizedBox(height: 5),
                        Text(
                          submissionState.fileStatusLabel,
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove ${attachments[index].displayName}',
                    onPressed: submitting || onRemoveFile == null
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
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                submissionState.isReady
                    ? Icons.check_circle_outline_rounded
                    : Icons.lock_outline_rounded,
                color: _statusColor,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _disclosureText,
                  style: const TextStyle(
                    color: Color(0xFF9EB6BE),
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (submissionError?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF35131A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8D3344)),
              ),
              child: Text(
                submissionError!,
                style: const TextStyle(
                  color: Color(0xFFFFB7C1),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (submissionState.isReady)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF103D31),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFF62D6A7)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_rounded, color: Color(0xFF62D6A7)),
                  const SizedBox(width: 9),
                  Text(
                    submissionState.buttonLabel(attachments.length),
                    style: const TextStyle(
                      color: Color(0xFFD9FFF0),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: submitting || onSubmitFiles == null
                    ? null
                    : () => onSubmitFiles!(),
                style: FilledButton.styleFrom(
                  backgroundColor: submissionState.isFailed
                      ? const Color(0xFFFF7A8C)
                      : const Color(0xFF62D6A7),
                  foregroundColor: const Color(0xFF03110E),
                  disabledBackgroundColor: const Color(0xFF1C4A52),
                  disabledForegroundColor: const Color(0xFFB8CBD1),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: submitting
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Color(0xFFBFEFF4),
                        ),
                      )
                    : Icon(
                        submissionState.isFailed
                            ? Icons.refresh_rounded
                            : Icons.cloud_upload_rounded,
                      ),
                label: Text(
                  submissionState.buttonLabel(attachments.length),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
