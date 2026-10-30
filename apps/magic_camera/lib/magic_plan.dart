import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:korlix_magic_core/magic_theme.dart';

import 'magic_billing.dart';

class MagicPlan extends StatelessWidget {
  const MagicPlan({super.key, required this.billing});
  final MagicBillingService billing;
  Future<void> _openLink(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Open $uri in your browser.')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: billing,
    builder: (context, _) {
      final b = billing;
      return Scaffold(
        appBar: AppBar(
          title: const Text('More moments. More magic.'),
          actions: [
            IconButton(
              tooltip: 'Refresh plan',
              onPressed: b.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Center(child: MagicMark(size: 110)),
            const SizedBox(height: 24),
            const Text(
              'Your first two are on us.',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'Two successful photos, once per account. No card needed. Failed generations never use your allowance.',
              style: TextStyle(color: magicMuted, height: 1.5),
            ),
            const SizedBox(height: 22),
            if (b.plan['included'] == true)
              Card(
                color: magicPanel,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Magic Camera is included with your KORLIX ${b.plan['name'].toString().toUpperCase()} plan. Your allowance is shared across both apps; no additional subscription is needed.',
                  ),
                ),
              )
            else ...[
              for (final row in const [
                ('magic_camera_starter', 'Starter', 15, r'US $9.99'),
                ('magic_camera_plus', 'Plus', 40, r'US $19.99'),
              ])
                Card(
                  color: magicPanel,
                  child: RadioGroup<String>(
                    groupValue: b.selectedId,
                    onChanged: (id) {
                      if (!b.busy && id != null) b.select(id);
                    },
                    child: RadioListTile<String>(
                      value: row.$1,
                      title: Text(
                        '${row.$2} · ${b.products[row.$1]?.price ?? row.$4}/month',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${row.$3} magic photos each month · maximum image quality',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: b.readyToBuy ? b.buy : null,
                child: Text(
                  b.busy
                      ? 'Verifying…'
                      : b.apple
                      ? 'Upgrade with the App Store'
                      : 'Upgrade with Google Play',
                ),
              ),
              if (!b.readyToBuy && !b.busy && !b.loading)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    'New purchases are not available on this device yet. Existing Korlix Pro and Ultra members can use their included allowance.',
                    style: TextStyle(color: magicMuted),
                  ),
                ),
            ],
            if (b.loading) const LinearProgressIndicator(),
            if (b.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  b.error!,
                  style: const TextStyle(color: magicOrange),
                ),
              ),
            if (b.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(b.message!),
              ),
            const SizedBox(height: 18),
            if (b.supported)
              OutlinedButton(
                onPressed: b.busy ? null : b.restore,
                child: const Text('Restore purchases'),
              ),
            if (b.supported)
              TextButton(
                onPressed: () => _openLink(
                  context,
                  b.apple
                      ? Uri.parse(
                          'https://apps.apple.com/account/subscriptions',
                        )
                      : Uri.https(
                          'play.google.com',
                          '/store/account/subscriptions',
                          {'package': magicPlayPackage},
                        ),
                ),
                child: const Text('Manage or cancel subscription'),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Subscriptions renew monthly until canceled. The store confirmation shows your local price and tax. Included generations reset on the first day of each month (UTC) and do not roll over. Saving, sharing and reporting existing images remain available after your allowance runs out.',
                style: TextStyle(color: magicMuted, height: 1.5, fontSize: 12),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              children: [
                TextButton(
                  onPressed: () => _openLink(
                    context,
                    Uri.https('www.korlixdeveloper.com', '/privacy-policy'),
                  ),
                  child: const Text('Privacy policy'),
                ),
                TextButton(
                  onPressed: () => _openLink(
                    context,
                    Uri.https('www.korlixdeveloper.com', '/terms-of-use'),
                  ),
                  child: const Text('Terms of use'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
