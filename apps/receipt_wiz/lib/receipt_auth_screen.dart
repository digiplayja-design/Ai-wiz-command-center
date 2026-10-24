import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'receipt_auth.dart';

const receiptInk = Color(0xFF102B3E);
const receiptTeal = Color(0xFF00717A);

class ReceiptAuthScreen extends StatefulWidget {
  const ReceiptAuthScreen({super.key, required this.auth});
  final ReceiptAuthController auth;
  @override
  State<ReceiptAuthScreen> createState() => _ReceiptAuthScreenState();
}

class _ReceiptAuthScreenState extends State<ReceiptAuthScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  bool _signup = false, _busy = false, _obscure = true;
  bool _policies = false, _parentPermission = false;
  String? _ageBand, _error, _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _mode(bool signup) {
    setState(() {
      _signup = signup;
      _password.clear();
      _error = _notice = null;
      _obscure = true;
    });
  }

  Future<void> _openPolicy(String path) async {
    final uri = Uri.https('www.korlixdeveloper.com', '/$path');
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* The visible URL below remains a usable fallback. */
    }
    if (!opened && mounted) {
      setState(() => _error = 'Open $uri in your browser.');
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _error = 'Enter your KORLIX email address first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      await widget.auth.requestPasswordReset(_email.text);
      if (mounted) {
        setState(
          () => _notice =
              'If this email belongs to a KORLIX account, a reset link has been sent. '
              'After changing your password, return here to sign in. '
              'The new password will also work in KORLIX AI.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _existingAccount() async {
    final result = await showDialog<String>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => AlertDialog(
        key: const Key('existing-account-dialog'),
        scrollable: true,
        title: const Text('Your KORLIX account works here'),
        content: const Text(existingKorlixAccountMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'reset'),
            child: const Text('Forgot Password?'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'signin'),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _mode(false);
    if (result == 'reset') await _reset();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_signup) {
      String? error;
      if (_ageBand == null) {
        error = 'Select your age range.';
      } else if (_ageBand == 'under_16') {
        error = 'You must be at least 16 to create a KORLIX account.';
      } else if (_ageBand == '16_17' && !_parentPermission) {
        error = 'Users aged 16–17 need permission from a parent or guardian.';
      } else if (!_policies) {
        error = 'Please agree to the Terms of Use and acknowledge the Privacy Policy.';
      }
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    bool existing = false;
    try {
      final signedIn = await widget.auth.authenticate(
        email: _email.text,
        password: _password.text,
        signup: _signup,
        ageBand: _ageBand,
        acceptedPolicies: _policies,
        parentPermission: _parentPermission,
      );
      if (!mounted) return;
      if (signedIn) {
        TextInput.finishAutofillContext();
      } else {
        setState(() {
          _signup = false;
          _password.clear();
          _notice =
              'Check your email to confirm your KORLIX account. '
              'Then return to Receipt Wiz and sign in. '
              'Already use KORLIX AI? Sign in with your existing email and password.';
        });
      }
    } on ReceiptAuthException catch (error) {
      existing = _signup && error.existingAccount;
      if (mounted && !existing) {
        setState(() {
          if (error.emailUnconfirmed) {
            _notice = 'Confirm your email using the link from KORLIX, then return here to sign in.';
            _password.clear();
            _signup = false;
          } else {
            _error = error.message;
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (existing && mounted) await _existingAccount();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Stack(
      children: [
        const Positioned.fill(
          child: ExcludeSemantics(child: CustomPaint(painter: _CircuitLines())),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 510),
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(17),
                              child: Image.asset(
                                'assets/korlix_logo.png',
                                width: 54,
                                height: 54,
                                excludeFromSemantics: true,
                              ),
                            ),
                            const SizedBox(width: 13),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'KORLIX',
                                    style: TextStyle(
                                      letterSpacing: 2.4,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: receiptTeal,
                                    ),
                                  ),
                                  Text(
                                    'Receipt Wiz',
                                    style: TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      color: receiptInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 36),
                        Semantics(
                          header: true,
                          child: Text(
                            _signup
                                ? 'One account.\nEvery receipt.'
                                : 'Your receipts.\nAll together.',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              height: 1.12,
                              color: receiptInk,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _signup
                              ? 'Create your free KORLIX account to scan, organize, and find your receipts.'
                              : 'Scan a receipt. Keep the original. Find it when it matters.',
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: Color(0xFF486372),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF8F5),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFB8DED9)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Already use KORLIX AI?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: receiptInk,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Use your existing email and password. Your receipts stay connected.',
                                style: TextStyle(
                                  color: receiptInk,
                                  height: 1.4,
                                ),
                              ),
                              if (_signup)
                                TextButton(
                                  onPressed: _busy ? null : () => _mode(false),
                                  child: const Text(
                                    'Sign in with my KORLIX account',
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        TextFormField(
                          key: const Key('receipt-email'),
                          controller: _email,
                          enabled: !_busy,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          validator: (v) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v?.trim() ?? '')
                              ? null
                              : 'Enter a valid email address.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: ValueKey('receipt-password-$_signup'),
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          autofillHints: [
                            _signup
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            labelText: _signup
                                ? 'Create password'
                                : 'KORLIX password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) => v?.isNotEmpty != true
                              ? 'Enter your password.'
                              : _signup && v!.length < 6
                              ? 'Use at least 6 characters.'
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_signup) ...[
                          const SizedBox(height: 20),
                          DropdownButtonFormField<String>(
                            key: const Key('receipt-age'),
                            initialValue: _ageBand,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Your age range',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'under_16',
                                child: Text('Under 16'),
                              ),
                              DropdownMenuItem(
                                value: '16_17',
                                child: Text('16–17'),
                              ),
                              DropdownMenuItem(
                                value: '18_plus',
                                child: Text('18 or older'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _ageBand = value),
                          ),
                          if (_ageBand == '16_17')
                            CheckboxListTile(
                              value: _parentPermission,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(
                                      () => _parentPermission = v ?? false,
                                    ),
                              title: const Text(
                                'I have permission from a parent or guardian.',
                              ),
                            ),
                          CheckboxListTile(
                            key: const Key('receipt-policies'),
                            value: _policies,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _policies = v ?? false),
                            title: const Text(
                              'I agree to the Terms of Use and acknowledge the Privacy Policy.',
                            ),
                          ),
                        ] else
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _reset,
                              child: const Text('Forgot Password?'),
                            ),
                          ),
                        if (_error != null || _notice != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Container(
                                key: const Key('receipt-auth-feedback'),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _error != null
                                      ? const Color(0xFFFFF1EC)
                                      : const Color(0xFFEAF8F5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _error ?? _notice!,
                                  style: const TextStyle(
                                    color: receiptInk,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        FilledButton(
                          key: const Key('receipt-auth-submit'),
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    semanticsLabel: 'Connecting to KORLIX',
                                  ),
                                )
                              : Text(
                                  _signup ? 'Create free account' : 'Sign In',
                                ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _busy ? null : () => _mode(!_signup),
                          child: Text(
                            _signup
                                ? 'Already registered? Sign In'
                                : 'New to KORLIX? Create free account',
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Private receipt storage • Free scanning • One KORLIX account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Color(0xFF486372),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => _openPolicy('terms.html'),
                              child: const Text('Terms of Use'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _openPolicy('privacy-policy.html'),
                              child: const Text('Privacy Policy'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CircuitLines extends CustomPainter {
  const _CircuitLines();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF00717A).withValues(alpha: .06)
      ..strokeWidth = 1;
    for (var x = 14.0; x < size.width; x += 54) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 10.0; y < size.height; y += 54) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
