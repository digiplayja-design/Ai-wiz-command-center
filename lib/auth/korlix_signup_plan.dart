import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../billing/korlix_apple_billing.dart';

/// Only a preference to open a review screen; never a subscription entitlement.
class KorlixSignupPlanIntent {
  static String _key(String userId) => 'korlix_signup_plan_v1_$userId';
  static Future<void> save(String? userId, String tier) async {
    if (userId == null || !['ultra', 'pro', 'basic'].contains(tier)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), tier);
  }

  static String? userId(String? token) {
    try {
      final body = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(token!.split('.')[1])),
        ),
      );
      return body['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> read(String? token) async {
    final id = userId(token);
    if (id == null) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('${_key(id)}_reviewed') == true) return null;
    final saved = prefs.getString(_key(id));
    if (saved != null) return saved;
    // Metadata is only a review preference, never permission or paid access.
    try {
      final body = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(token!.split('.')[1])),
        ),
      );
      final intent = body['user_metadata']?['korlix_signup_plan'];
      return ['ultra', 'pro', 'basic'].contains(intent)
          ? intent as String
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String? token) async {
    final id = userId(token);
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${_key(id)}_reviewed', true);
      await prefs.remove(_key(id));
    }
  }
}

class KorlixSignupPlanPicker extends StatefulWidget {
  const KorlixSignupPlanPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.billing,
  });
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final KorlixAppleBillingService? billing;
  @override
  State<KorlixSignupPlanPicker> createState() => _SignupPlanPickerState();
}

class _SignupPlanPickerState extends State<KorlixSignupPlanPicker> {
  late final service = widget.billing ?? KorlixAppleBillingService.instance;
  @override
  void initState() {
    super.initState();
    if (service.isStorePlatform) unawaited(service.refreshProducts());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Choose your plan',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('signup-trial-summary'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF7FA),
            border: Border.all(color: const Color(0xFF007A91)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  '3-day free trial',
                  style: TextStyle(
                    color: Color(0xFF006476),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'For eligible new Ultra and Pro subscribers.',
                style: TextStyle(
                  color: Color(0xFF102D3B),
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${service.isStorePlatform ? '' : 'Activate in the Android or iOS app. '}'
                'After the trial, your plan automatically renews monthly at the '
                'store price unless canceled. The store confirms eligibility '
                'before you subscribe.',
                style: const TextStyle(color: Color(0xFF405865), height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final tier in const ['ultra', 'pro', 'basic']) ...[
          _card(tier),
          const SizedBox(height: 10),
        ],
        Text(
          service.isStorePlatform
              ? 'Create and verify your account first. A trial starts only after '
                    'you confirm it with the store. Eligible trials last 3 days, then renew '
                    'monthly at the displayed price unless canceled. You can keep Basic '
                    'without starting a subscription.'
              : 'Create and verify your account here, then sign in to the Android or iOS app '
                    'to activate an eligible 3-day trial. Trials renew monthly at the store price '
                    'unless canceled. Basic remains free.',
          style: const TextStyle(color: Color(0xFF405865), height: 1.5),
        ),
      ],
    ),
  );

  Widget _card(String tier) {
    final basic = tier == 'basic';
    final ultra = tier == 'ultra';
    final selected = widget.value == tier;
    final productId = ultra ? service.ultraProductId : service.proProductId;
    final price = basic ? 'Free' : service.renewalPriceFor(productId);
    final trial = !basic && service.hasThreeDayTrial(productId);
    final title = ultra
        ? 'Ultra'
        : basic
        ? 'Basic'
        : 'Pro';
    final details = basic
        ? 'Most features are extremely limited.'
        : ultra
        ? 'Our highest individual plan. Higher limits, LIVE CONVO and no ads.'
        : 'More room for everyday creation, documents and exports.';
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: OutlinedButton(
        key: Key('signup-plan-$tier'),
        onPressed: widget.enabled ? () => widget.onChanged(tier) : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF102D3B),
          backgroundColor: selected ? const Color(0xFFF0FAFC) : Colors.white,
          padding: const EdgeInsets.all(18),
          side: BorderSide(
            color: selected || ultra
                ? const Color(0xFF007A91)
                : const Color(0xFF879EA9),
            width: selected ? 2.5 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ultra) ...[
              const Text(
                'RECOMMENDED',
                style: TextStyle(
                  color: Color(0xFF006C80),
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: const Color(0xFF006C80),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              details,
              style: TextStyle(
                height: 1.4,
                fontWeight: basic ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              basic
                  ? 'Free • No subscription'
                  : trial
                  ? '3-day free trial, then $price / month'
                  : price != null
                  ? '$price / month • 3-day free trial subject to store eligibility'
                  : '3-day free trial if eligible • Store price shown before confirmation',
              style: const TextStyle(
                color: Color(0xFF006476),
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
