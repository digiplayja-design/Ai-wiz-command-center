import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:korlix_receipt_core/receipt_wiz/receipt_wiz_style.dart';

import 'receipt_billing.dart';

class ReceiptPlanScreen extends StatefulWidget {
  const ReceiptPlanScreen({super.key, required this.billing});
  final ReceiptBillingService billing;
  @override
  State<ReceiptPlanScreen> createState() => _ReceiptPlanScreenState();
}

class _ReceiptPlanScreenState extends State<ReceiptPlanScreen> {
  String? _linkError;
  Future<void> _open(Uri uri) async {
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* Visible fallback below. */
    }
    if (!opened && mounted) {
      setState(() => _linkError = 'Open $uri in your browser.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.billing,
    builder: (context, _) {
      final b = widget.billing;
      return Scaffold(
        appBar: AppBar(title: const Text('Your Receipt Wiz plan')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6431B1), Color(0xFFAA3768)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.workspace_premium_outlined,
                    color: wizMint,
                    size: 42,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'More receipts.\nLess to think about.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    b.full ? 'Receipt Wiz Full is active' : 'Receipt Wiz Full',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    b.plan['included'] == true
                        ? 'Included with your KORLIX account'
                        : '${b.price ?? r'US $8.99'} / month',
                    style: const TextStyle(
                      color: wizMint,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _feature(
              '1,000 AI scans every month',
              Icons.auto_awesome_outlined,
              wizTeal,
            ),
            _feature(
              'Up to 5,000 saved receipts within 2 GB',
              Icons.inventory_2_outlined,
              wizCoral,
            ),
            _feature(
              'Search, categories and CSV export',
              Icons.manage_search_outlined,
              wizGreen,
            ),
            _feature(
              'The same shared KORLIX receipt library',
              Icons.hub_outlined,
              wizAmber,
            ),
            const SizedBox(height: 16),
            if (b.plan['included'] == true)
              const Text(
                'Your Pro, Ultra, Enterprise or developer access already includes Full. No extra subscription is needed.',
                style: TextStyle(
                  color: wizGreen,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (!b.full) ...[
              FilledButton.icon(
                key: const Key('receipt-subscribe'),
                onPressed: b.readyToBuy ? b.buy : null,
                icon: const Icon(Icons.workspace_premium_outlined),
                label: Text(
                  b.busy
                      ? 'Please wait…'
                      : b.price == null
                      ? 'Loading Google Play price…'
                      : 'Subscribe · ${b.price}/month',
                ),
              ),
              if (!b.loading && (!b.billingEnabled || b.product == null))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Purchases are not available on this device yet. Refresh your plan or try again later.',
                    style: TextStyle(color: wizMuted),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Monthly subscription, billed through Google Play. Automatically renews until canceled. '
              'Cancel in Google Play; access continues through the paid period. '
              'AI scan allowances reset on the 1st of each calendar month (UTC), do not roll over, and are shared across KORLIX apps. '
              'Failed scans are returned to your allowance. Local price and applicable taxes appear in Google Play before you confirm.',
              style: TextStyle(color: wizMuted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 18),
            wizPanel(
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Free stays useful',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: wizInk,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '20 AI scans per month • 100 saved receipts within 250 MB.\n'
                    'Manual details, search and CSV export remain available. Reaching a limit or canceling never deletes your saved receipts.',
                    style: TextStyle(color: wizMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (b.error != null || b.message != null || _linkError != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _linkError ?? b.error ?? b.message!,
                    style: TextStyle(
                      color: b.error != null ? wizCoral : wizGreen,
                    ),
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: b.busy || !b.supported ? null : b.restore,
                  child: const Text('Restore purchases'),
                ),
                TextButton(
                  onPressed: b.loading || b.busy ? null : b.refresh,
                  child: const Text('Refresh plan'),
                ),
                if (b.entitlement.isNotEmpty)
                  TextButton(
                    onPressed: () => _open(
                      Uri.https(
                        'play.google.com',
                        '/store/account/subscriptions',
                        {
                          'sku': receiptFullProductId,
                          'package': receiptPlayPackage,
                        },
                      ),
                    ),
                    child: const Text('Manage subscription'),
                  ),
                TextButton(
                  onPressed: () => _open(
                    Uri.https(
                      'www.korlixdeveloper.com',
                      '/subscription-terms.html',
                    ),
                  ),
                  child: const Text('Subscription terms'),
                ),
                TextButton(
                  onPressed: () => _open(
                    Uri.https(
                      'www.korlixdeveloper.com',
                      '/privacy-policy.html',
                    ),
                  ),
                  child: const Text('Privacy policy'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  Widget _feature(String text, IconData icon, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: wizInk,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
