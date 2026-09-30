import 'package:flutter/material.dart';
import 'scheduling_client.dart';
import 'scheduling_voice.dart';

class SchedulingVoicePanel extends StatelessWidget {
  const SchedulingVoicePanel({
    super.key,
    required this.controller,
    required this.onApprove,
    required this.onDismiss,
  });
  final SchedulingVoiceController controller;
  final Future<void> Function()? onApprove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.available) return const SizedBox.shrink();
      final result = controller.result;
      if (!controller.busy && result.isEmpty && controller.readback.isEmpty) {
        return const SizedBox.shrink();
      }
      final color = Theme.of(context).colorScheme;
      String time(SchedulingMap value, String field) {
        try {
          return schedulingVoiceTime(value, field);
        } catch (_) {
          return 'Time unavailable';
        }
      }

      final bookings = schedulingItems(result['bookings']);
      final slots = schedulingItems(result['slots']);
      return Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KORLIX 2MEETU',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (controller.busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 10),
                  const Text('Checking your schedule…'),
                ],
                if (result['message'] is String &&
                    result['requires_confirmation'] != true)
                  Text(result['message'] as String),
                if (result['profile_ready'] == false)
                  const Text(
                    'Save your host name and availability in 2MEETU to begin.',
                  ),
                if (result['timezone'] != null)
                  Text('Host timezone: ${result['timezone']}'),
                if (result['kind'] == 'context' &&
                    result['profile_ready'] != false) ...[
                  const SizedBox(height: 8),
                  Text(
                    bookings.isEmpty
                        ? 'No appointments in the returned results.'
                        : 'Appointments',
                  ),
                  for (final booking in bookings)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${booking['title']} · ${booking['guest_name']}\n${time(booking, 'starts_at')} to ${time(booking, 'ends_at')}\n${booking['state']}',
                      ),
                    ),
                  if (schedulingItems(result['events']).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Event types'),
                    for (final event in schedulingItems(result['events']))
                      Text(
                        '${event['title']} · ${event['duration_minutes']} minutes · ${event['state']}',
                      ),
                  ],
                ],
                if (result['kind'] == 'slots') ...[
                  const SizedBox(height: 8),
                  Text(
                    slots.isEmpty
                        ? 'No available times in this search.'
                        : 'Available times',
                  ),
                  for (final slot in slots.take(40))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${time(slot, 'starts_at')} to ${time(slot, 'ends_at')}',
                      ),
                    ),
                  if (slots.length > 40)
                    const Text(
                      'Showing the first 40 times. Open the booking page for more.',
                    ),
                  const SizedBox(height: 8),
                  const Text('Availability is checked again when booked.'),
                ],
                if (result['truncated'] == true) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'These results are partial. Open 2MEETU for the full schedule.',
                  ),
                ],
                if (controller.readback.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    controller.pendingProposalId != null
                        ? 'Review the exact change'
                        : 'Schedule details',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(controller.readback),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (controller.pendingProposalId != null)
                      FilledButton(
                        onPressed: controller.busy ? null : onApprove,
                        child: Text(
                          controller.needsStatusCheck
                              ? 'Review status and retry'
                              : 'Approve change',
                        ),
                      ),
                    TextButton(
                      onPressed: onDismiss,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
