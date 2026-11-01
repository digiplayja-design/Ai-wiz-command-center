import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brain_billing.dart';

class BrainBillingScreen extends StatelessWidget {
  const BrainBillingScreen({super.key, required this.billing});
  final BrainBilling billing;
  String minutes(Object? seconds) =>
      ((seconds as num? ?? 0) / 60).toStringAsFixed(1);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plan & AI GAS')),
    body: ListenableBuilder(
      listenable: billing,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Keep the conversation going',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          if (billing.balance != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${minutes(billing.balance!['remainingSeconds'])} Live minutes available',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${minutes(billing.balance!['includedSeconds'])} included · ${minutes(billing.balance!['gasSeconds'])} AI GAS',
                    ),
                    const Text(
                      'Minutes reserved for an active conversation are shown again when that conversation ends.',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Brain+Voice Monthly',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Your personal Brain, trainable Rici and 60 Live Conversation minutes each billing month.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        billing.enabled &&
                            !billing.busy &&
                            !billing.subscriptionActive
                        ? () => billing.buy(billing.monthly)
                        : null,
                    child: Text(
                      billing.subscriptionActive
                          ? 'Plan active'
                          : billing.products[billing.monthly] == null
                          ? 'Plan unavailable'
                          : '${billing.products[billing.monthly]!.price} / month',
                    ),
                  ),
                  const Text(
                    'Auto-renews monthly until canceled in your store account. Included minutes reset each billing month and do not roll over. Deep Think follows its separate account limits.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Add AI GAS', style: Theme.of(context).textTheme.titleLarge),
          const Text(
            'One-time purchases for Live Conversation. Included minutes are used first. Unused AI GAS carries over and does not expire. AI GAS does not extend Deep Think.',
          ),
          for (final hours in [1, 2, 3])
            Card(
              child: ListTile(
                title: Text('${hours * 60} extra minutes'),
                subtitle: const Text('One-time AI GAS top-up'),
                trailing: FilledButton(
                  onPressed: billing.enabled && !billing.busy
                      ? () => billing.buy(billing.gas(hours))
                      : null,
                  child: Text(
                    billing.products[billing.gas(hours)]?.price ??
                        'Unavailable',
                  ),
                ),
              ),
            ),
          if (billing.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(liveRegion: true, child: Text(billing.message!)),
            ),
          if (billing.loading) const LinearProgressIndicator(),
          TextButton(
            onPressed: billing.busy ? null : billing.restore,
            child: const Text('Restore / retry purchases'),
          ),
          TextButton(
            onPressed: billing.loading ? null : billing.refresh,
            child: const Text('Refresh balance'),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(
                billing.apple ? 'https://apps.apple.com/account/subscriptions' : 'https://play.google.com/store/account/subscriptions?package=com.korlix.brain',
              ),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Manage subscription'),
          ),
          const Text(
            'Purchases stay with the KORLIX account used at checkout. Sign in with that account to use your saved AI GAS on another device.',
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.korlixdeveloper.com/terms.html'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Terms'),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://www.korlixdeveloper.com/privacy-policy.html',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Privacy'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
