import 'package:flutter/material.dart';
import '../bookkeeping/bookkeeping_client.dart';
import '../privacy/korlix_third_party_ai_consent.dart';
import 'receipt_wiz_client.dart';
import 'receipt_wiz_screen.dart';

Future<void> openReceiptWiz(
  BuildContext context, {
  required String backendBaseUrl,
  required Map<String, String> Function() headersBuilder,
  Listenable? sessionChanges,
  int? year,
  String? businessId,
  String? taxWorkspaceId,
  bool inboxOnly = false,
}) async {
  final client = ReceiptWizClient(
    backendBaseUrl: backendBaseUrl,
    headersBuilder: headersBuilder,
    sessionChanges: sessionChanges,
  );
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReceiptWizScreen(
        client: client,
        initialYear: year,
        businessId: businessId,
        taxWorkspaceId: taxWorkspaceId,
        inboxOnly: inboxOnly,
        ensureConsent: () => ensureKorlixThirdPartyAiConsent(
          context: context,
          featureName: 'THE RECEIPT WIZ',
          providers: const {KorlixThirdPartyAiProvider.openAi},
          dataCategories: const {
            KorlixThirdPartyAiDataCategory.imagesAndPhotos,
            KorlixThirdPartyAiDataCategory.filesAndDocuments,
          },
        ),
      ),
    ),
  );
}

class ReceiptWizEntry extends StatelessWidget {
  const ReceiptWizEntry({
    super.key,
    required this.client,
    this.year,
    this.businessId,
    this.taxWorkspaceId,
    this.onReturn,
  });
  final BookkeepingClient client;
  final int? year;
  final String? businessId, taxWorkspaceId;
  final Future<void> Function()? onReturn;
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFEAF8F5),
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      leading: const Icon(
        Icons.document_scanner_outlined,
        color: Color(0xFF007F89),
        size: 30,
      ),
      title: const Text(
        'THE RECEIPT WIZ',
        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF102B3E)),
      ),
      subtitle: Text(
        year == null
            ? 'Your automatically shared receipt inbox · Free'
            : 'Shared receipts for $year · Undated receipts need review',
        style: const TextStyle(color: Color(0xFF456577)),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: client.sessionChanged
          ? null
          : () async {
              await openReceiptWiz(
                context,
                backendBaseUrl: client.backendBaseUrl,
                headersBuilder: client.headersBuilder,
                sessionChanges: client.sessionChanges,
                year: year,
                businessId: businessId,
                taxWorkspaceId: taxWorkspaceId,
                inboxOnly: true,
              );
              await onReturn?.call();
            },
    ),
  );
}
