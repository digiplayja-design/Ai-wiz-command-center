import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brain_auth.dart';

class BrainAuthScreen extends StatefulWidget {
  const BrainAuthScreen({super.key, required this.auth});
  final BrainAuthController auth;
  @override
  State<BrainAuthScreen> createState() => _BrainAuthScreenState();
}

class _BrainAuthScreenState extends State<BrainAuthScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _signup = false,
      _busy = false,
      _obscure = true,
      _policies = false,
      _parent = false;
  String? _age, _message;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({bool reset = false}) async {
    if (_busy) return;
    if (reset) {
      if (!_email.text.contains('@')) {
        setState(() => _message = 'Enter your email address first.');
        return;
      }
    } else if (!_form.currentState!.validate()) {
      return;
    }
    if (_signup &&
        !reset &&
        (_age == null ||
            _age == 'under_16' ||
            !_policies ||
            (_age == '16_17' && !_parent))) {
      setState(
        () => _message = 'You must be at least 16, accept the policies, and have parent or guardian permission if you are under 18.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (reset) {
        await widget.auth.requestPasswordReset(_email.text);
        if (mounted) {
          setState(
            () => _message = 'If this email has an account, a password reset link has been sent.',
          );
        }
      } else {
        final signedIn = await widget.auth.authenticate(
          email: _email.text,
          password: _password.text,
          signup: _signup,
          ageBand: _age,
          acceptedPolicies: _policies,
          parentPermission: _parent,
        );
        _password.clear();
        if (!signedIn && mounted) {
          setState(() {
            _signup = false;
            _message =
                'Check your email to confirm your account, then sign in here.';
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is BrainAuthException && error.existingAccount
              ? existingKorlixAccountMessage
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _policy(String page) async {
    final uri = Uri.https('www.korlixdeveloper.com', '/$page');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _message = 'Open $uri in your browser.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.psychology_outlined,
                      color: Color(0xFF6AEAFF),
                      size: 72,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'KORLIX',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 44,
                        letterSpacing: 7,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Text(
                      'B R A I N',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      _signup
                          ? 'Create your KORLIX account'
                          : 'Welcome to your brain',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use the same account as KORLIX AI. Your approved behaviors and memories stay connected.',
                      style: TextStyle(color: Color(0xFFD6CBE0)),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) =>
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Enter a valid email.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autofillHints: [
                        _signup
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          (value?.length ?? 0) < (_signup ? 8 : 1)
                          ? 'Enter ${_signup ? 'at least 8 characters' : 'your password'}.'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_signup) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _age,
                        decoration: const InputDecoration(
                          labelText: 'Age range',
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
                            : (v) => setState(() => _age = v),
                      ),
                      if (_age == '16_17')
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _parent,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _parent = v ?? false),
                          title: const Text(
                            'I have parent or guardian permission.',
                          ),
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _policies,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _policies = v ?? false),
                        title: const Text(
                          'I agree to the Terms of Use and acknowledge the Privacy Policy.',
                        ),
                      ),
                    ],
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _message!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : () => _submit(),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_signup ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _signup = !_signup;
                              _message = null;
                              _password.clear();
                            }),
                      child: Text(
                        _signup
                            ? 'I already have an account'
                            : 'Create an account',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _submit(reset: true),
                      child: const Text('Forgot password?'),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => _policy('terms.html'),
                          child: const Text('Terms of Use'),
                        ),
                        TextButton(
                          onPressed: () => _policy('privacy-policy.html'),
                          child: const Text('Privacy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
