import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'brand.dart';

enum _AuthMode { signIn, signUp, resetPassword }

class PolicyLinks extends StatelessWidget {
  const PolicyLinks({
    super.key,
    required this.apiOrigin,
    this.showSubscription = true,
    this.showSupport = true,
    this.showAppleEula = false,
  });
  final String apiOrigin;
  final bool showSubscription, showSupport, showAppleEula;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      _link(context, 'Terms of Use', '$apiOrigin/esha/terms'),
      _link(context, 'Privacy Policy', '$apiOrigin/esha/privacy'),
      if (showSubscription)
        _link(
          context,
          'Subscription terms',
          '$apiOrigin/esha/terms#offer-heading',
        ),
      if (showAppleEula)
        _link(
          context,
          'Apple standard EULA',
          'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
        ),
      if (showSupport)
        _link(
          context,
          'Contact support',
          'https://www.korlixdeveloper.com/support.html',
        ),
    ],
  );
  Widget _link(BuildContext context, String label, String url) =>
      TextButton(onPressed: () => openSource(context, url), child: Text(label));
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.controller});
  final EshaController controller;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool obscure = true, deleting = false, resetBusy = false;
  bool termsAccepted = false,
      privacyAcknowledged = false,
      parentPermission = false;
  String ageBand = '';
  String? authMessage, localAuthError;
  _AuthMode authMode = _AuthMode.signIn;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          profile = widget.controller.vanity.beautyProfile;
      return Scaffold(
        appBar: AppBar(title: const Text('Your beauty space')),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PageHeading(
                        'ESHA BY KORLIX',
                        'A little more you.',
                        'Your profile, your collection and your membership, in one place.',
                      ),
                      if (c.session == null)
                        _authPanel(c)
                      else
                        EshaPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'YOUR KORLIX ACCOUNT',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: pink,
                                  letterSpacing: 1.8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                c.session!.email,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: c.authBusy
                                    ? null
                                    : () async {
                                        await c.signOut();
                                        if (mounted) {
                                          _setAuthMode(_AuthMode.signIn);
                                        }
                                      },
                                icon: const Icon(Icons.logout, size: 18),
                                label: const Text('Sign out on this device'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      EshaPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Beauty profile',
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 25,
                              ),
                            ),
                            const SizedBox(height: 18),
                            ChoiceGroup(
                              label: 'Your undertone, if you know it',
                              options: const {
                                'not_sure': 'Not sure',
                                'warm': 'Warm',
                                'cool': 'Cool',
                                'neutral': 'Neutral',
                                'olive': 'Olive',
                              },
                              value: profile.undertone,
                              onChanged: c.sync.canEdit
                                  ? (v) => c.setProfile(
                                      BeautyProfile(
                                        undertone: v,
                                        shareWithEsha: profile.shareWithEsha,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'A preference you choose, not a diagnosis or automatic shade match.',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            const SizedBox(height: 10),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: profile.shareWithEsha,
                              onChanged: c.sync.canEdit
                                  ? (v) => c.setProfile(
                                      BeautyProfile(
                                        undertone: profile.undertone,
                                        shareWithEsha: v,
                                      ),
                                    )
                                  : null,
                              title: const Text('Share preferences with Esha'),
                              subtitle: const Text(
                                'Include your beauty preferences, selected edit and owned-product IDs with live questions. Off by default.',
                              ),
                            ),
                            if (c.aiSharingConsented)
                              TextButton(
                                onPressed: () => c.setAiSharingConsent(false),
                                child: const Text('Stop sharing with OpenAI'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      EshaPanel(
                        color: blush,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Esha membership',
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 25,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              c.hasAppAccess
                                  ? 'Your store membership is active.'
                                  : '3 days free for eligible subscribers, then US \$4.99 per month. Local price and eligibility come from your store.',
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      MembershipScreen(controller: c),
                                ),
                              ),
                              child: const Text('View membership'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      EshaPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'About your data',
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 23,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Your saved collection stays on this device and signed-in collections sync to your Korlix account. An active Esha trial or subscription is required to use the beauty features. Live consultation requests are processed by Korlix and its AI service. Requests and answers may be retained for request replay and usage accounting. Pending questions are saved securely so a retry can use the same request ID.',
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Esha does not use camera access or infer your skin tone. Passwords are not saved by the app. Session tokens use your device’s secure storage.',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            const SizedBox(height: 12),
                            PolicyLinks(
                              apiOrigin: c.api.config.apiOrigin,
                              showAppleEula: c.api.platform == 'ios',
                            ),
                            if (c.session != null) ...[
                              const Divider(height: 28),
                              const Text(
                                'Account deletion',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'You can request deletion of your Korlix account. This affects your Korlix account and associated services, including Esha. Store subscriptions must be managed separately.',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                              const SizedBox(height: 10),
                              TextButton.icon(
                                onPressed: deleting ? null : _requestDeletion,
                                icon: const Icon(Icons.person_remove_outlined),
                                label: const Text(
                                  'Request Korlix account deletion',
                                ),
                              ),
                              TextButton(
                                onPressed: c.purchases.manage,
                                child: const Text('Manage store subscription'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Center(
                        child: Text(
                          'ESHA BY KORLIX\nBeauty, thoughtfully yours.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: muted,
                            height: 1.8,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _authPanel(EshaController c) {
    final creating = authMode == _AuthMode.signUp;
    final resetting = authMode == _AuthMode.resetPassword;
    final busy = c.authBusy || resetBusy;
    return EshaPanel(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              creating
                  ? 'Create your Korlix account'
                  : resetting
                  ? 'Reset your password'
                  : 'Sign in to Korlix',
              style: const TextStyle(fontFamily: 'Georgia', fontSize: 25),
            ),
            const SizedBox(height: 10),
            Text(
              creating
                  ? 'One account for your Esha collection. Already use Korlix? Sign in with the same email.'
                  : resetting
                  ? 'Enter your account email. Follow the link in your email to choose a new password, then return to Esha.'
                  : 'Sync your Esha collection and manage membership with your Korlix account.',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('auth-email'),
              controller: email,
              enabled: !busy,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: resetting
                  ? TextInputAction.done
                  : TextInputAction.next,
              autocorrect: false,
              onSubmitted: resetting ? (_) => _submitAuth() : null,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            if (!resetting) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('auth-password'),
                controller: password,
                enabled: !busy,
                autofillHints: [
                  creating ? AutofillHints.newPassword : AutofillHints.password,
                ],
                obscureText: obscure,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: creating
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: creating ? null : (_) => _submitAuth(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: creating ? 'At least 6 characters' : null,
                  suffixIcon: IconButton(
                    tooltip: obscure ? 'Show password' : 'Hide password',
                    onPressed: busy
                        ? null
                        : () => setState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
            if (creating) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('auth-confirm-password'),
                controller: confirmPassword,
                enabled: !busy,
                autofillHints: const [AutofillHints.newPassword],
                obscureText: obscure,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
              ),
              const SizedBox(height: 20),
              ChoiceGroup(
                label: 'Your age range',
                options: const {'16_17': '16–17', '18_plus': '18 or older'},
                value: ageBand,
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        ageBand = value;
                        parentPermission = false;
                      }),
              ),
              const SizedBox(height: 8),
              const Text(
                'Korlix accounts are for ages 16 and older.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              if (ageBand == '16_17')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: parentPermission,
                  onChanged: busy
                      ? null
                      : (value) =>
                            setState(() => parentPermission = value == true),
                  title: const Text(
                    'I have permission from a parent or guardian.',
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: termsAccepted,
                onChanged: busy
                    ? null
                    : (value) => setState(() => termsAccepted = value == true),
                title: const Text('I agree to the Terms of Use.'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: privacyAcknowledged,
                onChanged: busy
                    ? null
                    : (value) =>
                          setState(() => privacyAcknowledged = value == true),
                title: const Text('I have read the Privacy Policy.'),
              ),
              PolicyLinks(
                apiOrigin: c.api.config.apiOrigin,
                showSubscription: false,
                showSupport: false,
              ),
              const SizedBox(height: 8),
              const Text(
                'Creating an account does not start a trial or subscribe you. You choose membership separately.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
            if (localAuthError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  localAuthError!,
                  style: const TextStyle(color: pink),
                ),
              ),
            if (authMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(authMessage!, style: const TextStyle(color: muted)),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('auth-submit'),
                onPressed: busy ? null : _submitAuth,
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        creating
                            ? 'Create account'
                            : resetting
                            ? 'Request reset link'
                            : 'Sign in',
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!creating)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _setAuthMode(_AuthMode.signUp),
                    child: const Text('Create account'),
                  ),
                if (creating || resetting)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _setAuthMode(_AuthMode.signIn),
                    child: const Text('Back to sign in'),
                  ),
                if (!resetting)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _setAuthMode(_AuthMode.resetPassword),
                    child: const Text('Forgot password?'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Your guest collection stays on this device. Signing in opens a separate account collection.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  void _setAuthMode(_AuthMode value) {
    setState(() {
      authMode = value;
      localAuthError = null;
      authMessage = null;
      password.clear();
      confirmPassword.clear();
      obscure = true;
    });
  }

  Future<void> _submitAuth() async {
    final c = widget.controller;
    if (c.authBusy || resetBusy) return;
    setState(() {
      localAuthError = null;
      authMessage = null;
    });
    if (authMode == _AuthMode.resetPassword) {
      setState(() => resetBusy = true);
      try {
        await c.api.requestPasswordReset(email.text);
        if (mounted) {
          setState(() {
            authMode = _AuthMode.signIn;
            authMessage = 'If this email belongs to a Korlix account, check for a reset link. After choosing your new password, sign in here.';
          });
        }
      } catch (error) {
        if (mounted) {
          setState(
            () => localAuthError = error is EshaException
                ? error.message
                : 'The reset request could not be confirmed. Please try again.',
          );
        }
      } finally {
        if (mounted) setState(() => resetBusy = false);
      }
      return;
    }
    bool signedIn;
    if (authMode == _AuthMode.signUp) {
      if (password.text != confirmPassword.text) {
        setState(() => localAuthError = 'The passwords do not match.');
        return;
      }
      final outcome = await c.signUp(
        email.text,
        password.text,
        ageBand: ageBand,
        termsAccepted: termsAccepted,
        privacyAcknowledged: privacyAcknowledged,
        parentPermission: parentPermission,
      );
      if (!mounted) return;
      signedIn = outcome == SignupOutcome.signedIn;
      if (outcome == SignupOutcome.confirmationRequired) {
        setState(() {
          authMode = _AuthMode.signIn;
          password.clear();
          confirmPassword.clear();
          authMessage = 'Check your email to confirm your account, then sign in here. If you already have a Korlix account, sign in or use Forgot password.';
        });
        return;
      }
    } else {
      signedIn = await c.signIn(email.text, password.text);
    }
    if (!mounted) return;
    if (signedIn) {
      password.clear();
      confirmPassword.clear();
      FocusScope.of(context).unfocus();
      showMessage(context, 'Your Korlix account collection is open.');
    } else {
      setState(() => localAuthError = c.authError);
    }
  }

  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Korlix account deletion?'),
        content: const Text(
          'This requests deletion of your whole Korlix account and associated account data, including Esha. It is not just clearing this app.\n\nDeleting an account does not automatically cancel an App Store or Google Play subscription. Manage the subscription separately to stop renewals.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep my account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deleting = true);
    try {
      final result = await widget.controller.requestDeletion();
      if (mounted) showMessage(context, result);
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          e is EshaException
              ? e.message
              : 'The request could not be confirmed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }
}

class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key, required this.controller});
  final EshaController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller,
          store = controller.purchases,
          status = controller.purchases.membership;
      final active = store.hasAppAccess;
      final price = store.localizedMonthlyPrice;
      final eligible = store.trialEligible == true;
      final String headline = active
          ? status.trial
                ? 'Your Esha trial is active.'
                : 'Your Esha membership.'
          : store.needsVerification
          ? 'Verify your Esha membership.'
          : store.catalogReady && price != null
          ? eligible
                ? '3 days to make it yours.'
                : 'Make Esha part of your routine.'
          : 'Your beauty companion, soon.';
      return Scaffold(
        appBar: AppBar(
          title: const Text('Esha membership'),
          actions: [
            IconButton(
              tooltip: 'Account, privacy and support',
              icon: const Icon(Icons.person_outline),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AccountScreen(controller: c),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EshaPanel(
                        color: plum,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/esha-korlix-pink.png',
                                width: 86,
                                height: 86,
                                semanticLabel: 'Pink Korlix app logo',
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              headline,
                              style: const TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 32,
                                height: 1.2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              active
                                  ? status.trial
                                        ? 'Your trial is active.'
                                        : price == null
                                        ? 'Your membership is active.'
                                        : '$price / month'
                                  : price == null
                                  ? 'PLANNED US OFFER\n3 days free, then US \$4.99 / month'
                                  : eligible
                                  ? '3 days free, then $price / month'
                                  : '$price / month',
                              style: const TextStyle(
                                color: Color(0xFFEAC2D3),
                                fontSize: 19,
                                height: 1.6,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              active
                                  ? 'Review your renewal price and billing date in Manage subscription.'
                                  : price == null
                                  ? 'Available after the store offer and membership service are ready. No payment or trial starts here yet.'
                                  : eligible
                                  ? 'The store has returned an eligible introductory offer. Review the final terms in the purchase sheet.'
                                  : 'The store has not returned an eligible free-trial offer for this account.',
                              style: const TextStyle(
                                color: Color(0xFFE9D7DE),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!active) ...[
                        Text(store.accessMessage),
                        const SizedBox(height: 16),
                      ],
                      const Text(
                        'A beauty space built around you',
                        style: TextStyle(fontFamily: 'Georgia', fontSize: 26),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'An active Esha trial or subscription unlocks product browsing, guided edits, your vanity and the look studio. Live AI consultations also use the allowance shown below.',
                      ),
                      const SizedBox(height: 16),
                      _feature(
                        Icons.auto_awesome_outlined,
                        'Live beauty consultations',
                        'Ask Esha about makeup, lip pairings, lashes and body-care preferences.',
                      ),
                      _feature(
                        Icons.tune,
                        'Thoughtful guided edits',
                        'Build from your budget, documented product details and what you already own.',
                      ),
                      _feature(
                        Icons.favorite_border,
                        'A vanity to come back to',
                        'Keep favorites, saved routines and illustrated looks together.',
                      ),
                      const SizedBox(height: 16),
                      EshaPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Consultation allowance',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              active && status.allowanceLimit != null
                                  ? '${status.remaining ?? 0} of ${status.allowanceLimit} consultations remaining this period.'
                                  : store.trialConsultationLimit != null &&
                                        store.monthlyConsultationLimit != null
                                  ? '${store.trialConsultationLimit} consultations during an eligible 3-day trial; ${store.monthlyConsultationLimit} consultations per monthly billing period after the trial.'
                                  : 'The consultation allowance has not been published yet. Membership purchases remain unavailable until it is configured.',
                            ),
                            if (status.reserved > 0)
                              Text(
                                '${status.reserved} consultation request(s) are being processed.',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            if (status.periodEndsAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Allowance period ends ${_date(status.periodEndsAt!)}.',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            if (active) ...[
                              const SizedBox(height: 10),
                              Text(
                                status.verificationFresh
                                    ? 'Membership verified by the store service.'
                                    : 'Membership verification needs to be refreshed.',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (status.expiresAt != null)
                              Text(
                                'Current store entitlement ends ${_date(status.expiresAt!)}.',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (store.loading || store.busy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: LinearProgressIndicator(),
                        ),
                      if (store.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            store.error!,
                            style: const TextStyle(color: pink),
                          ),
                        ),
                      if (store.message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            store.message!,
                            style: const TextStyle(color: muted),
                          ),
                        ),
                      if (status.warning != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            status.warning!,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 22),
                      if (c.session == null)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AccountScreen(controller: c),
                              ),
                            ),
                            child: const Text('Sign in or create an account'),
                          ),
                        )
                      else if (!active)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed:
                                store.busy ||
                                    store.loading ||
                                    store.awaitingApproval
                                ? null
                                : store.hasUnverifiedPurchase && !store.busy
                                ? store.retryVerification
                                : store.needsVerification
                                ? store.refresh
                                : store.canPurchase
                                ? store.purchase
                                : null,
                            child: Text(
                              store.awaitingApproval
                                  ? 'Awaiting store approval'
                                  : store.hasUnverifiedPurchase
                                  ? 'Verify existing purchase'
                                  : store.needsVerification
                                  ? 'Connect to verify membership'
                                  : store.canPurchase
                                  ? eligible
                                        ? 'Start 3-day free trial'
                                        : 'Subscribe for $price / month'
                                  : 'Membership coming soon',
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: store.busy || store.loading
                                ? null
                                : store.refresh,
                            child: const Text('Refresh status'),
                          ),
                          TextButton(
                            onPressed: store.supported && !store.busy
                                ? store.restore
                                : null,
                            child: const Text('Restore purchases'),
                          ),
                          TextButton(
                            onPressed: store.manage,
                            child: const Text('Manage subscription'),
                          ),
                          if (store.hasUnverifiedPurchase)
                            TextButton(
                              onPressed: store.busy
                                  ? null
                                  : store.retryVerification,
                              child: const Text('Retry verification'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'An eligible trial begins only after you confirm it with Apple or Google. The subscription renews automatically at the store’s displayed monthly price unless canceled under the store’s terms. A previously used trial may not be available again. Manage or cancel through your App Store or Google Play account.',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'An Esha membership is for Esha. It does not upgrade another Korlix plan. Cosmetics are purchased separately from their manufacturers; catalog estimates are not included in the membership price.',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PolicyLinks(
                        apiOrigin: c.api.config.apiOrigin,
                        showAppleEula: c.api.platform == 'ios',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _feature(IconData icon, String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: pink, size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  String _date(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    return date == null
        ? value
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
