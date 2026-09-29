import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';

bool validateBookkeepingForm(BuildContext context, GlobalKey<FormState> key) {
  final invalid = key.currentState!.validateGranularly();
  if (invalid.isEmpty) {
    FocusScope.of(context).unfocus();
    return true;
  }
  final field = invalid.first;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted || !field.mounted) return;
    Scrollable.ensureVisible(
      field.context,
      alignment: .15,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
    );
  });
  return false;
}

Rect bookkeepingShareOrigin(GlobalKey key, BuildContext context) {
  final bounds = Offset.zero & MediaQuery.sizeOf(context);
  final object = key.currentContext?.findRenderObject();
  if (object is RenderBox && object.attached && object.hasSize) {
    final rect = (object.localToGlobal(Offset.zero) & object.size).intersect(
      bounds,
    );
    if (!rect.isEmpty && rect.isFinite) return rect;
  }
  return Rect.fromLTWH(bounds.center.dx, bounds.center.dy, 1, 1);
}

void revealBookkeepingFeedback(GlobalKey key, bool Function() current) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = key.currentContext;
    if (!current() || context == null || !context.mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: .7,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
    );
  });
}

class BookkeepingSaveGuard extends StatefulWidget {
  const BookkeepingSaveGuard({
    super.key,
    required this.client,
    required this.busy,
    required this.child,
  });
  final BookkeepingClient client;
  final bool busy;
  final Widget child;
  @override
  State<BookkeepingSaveGuard> createState() => _BookkeepingSaveGuardState();
}

class _BookkeepingSaveGuardState extends State<BookkeepingSaveGuard> {
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.busy || widget.client.sessionChanged,
    child: widget.client.sessionChanged
        ? AlertDialog(
            title: const Text('Session changed'),
            content: const Text('Reopen Bookkeeping after signing in.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          )
        : widget.child,
  );
}

class BookkeepingDialog extends StatelessWidget {
  const BookkeepingDialog({
    super.key,
    this.client,
    this.busy = false,
    this.title,
    this.content,
    this.actions,
  });
  final BookkeepingClient? client;
  final bool busy;
  final Widget? title, content;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          errorMaxLines: 12,
        ),
      ),
      child: AlertDialog(title: title, content: content, actions: actions),
    );
    return client == null
        ? child
        : BookkeepingSaveGuard(client: client!, busy: busy, child: child);
  }
}

class BookkeepingPanel extends StatelessWidget {
  const BookkeepingPanel({
    super.key,
    required this.client,
    required this.busy,
    required this.child,
    this.insetPadding = const EdgeInsets.all(16),
  });
  final BookkeepingClient client;
  final bool busy;
  final Widget child;
  final EdgeInsets insetPadding;
  @override
  Widget build(BuildContext context) => BookkeepingSaveGuard(
    client: client,
    busy: busy,
    child: Dialog(insetPadding: insetPadding, child: child),
  );
}

class BookkeepingExportFeedback extends StatelessWidget {
  const BookkeepingExportFeedback({super.key, this.error, this.notice});
  final String? error, notice;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                error!,
                style: const TextStyle(color: Color(0xff9c2525)),
              ),
            ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(notice!),
            ),
        ],
      ),
    ),
  );
}
