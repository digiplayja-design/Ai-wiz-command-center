import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brain_auth.dart';
import 'brain_workspace.dart';

const brainPurple = Color(0xff100b1b);
const brainGold = Color(0xffffdf91);

class BrainApp extends StatefulWidget {
  const BrainApp({super.key, required this.auth});
  final BrainAuthController auth;
  @override
  State<BrainApp> createState() => _BrainAppState();
}

class _BrainAppState extends State<BrainApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.auth.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.auth.resume());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KORLIX Brain+Voice',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: brainPurple,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffa273ed),
        brightness: Brightness.dark,
        primary: brainGold,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      useMaterial3: true,
    ),
    home: ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        if (!widget.auth.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (widget.auth.session == null) return BrainSignIn(auth: widget.auth);
        return BrainWorkspace(
          key: ValueKey(widget.auth.revision),
          auth: widget.auth,
        );
      },
    ),
  );
}

class BrainSignIn extends StatefulWidget {
  const BrainSignIn({super.key, required this.auth});
  final BrainAuthController auth;
  @override
  State<BrainSignIn> createState() => _BrainSignInState();
}

class _BrainSignInState extends State<BrainSignIn> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _signup = false,
      _busy = false,
      _showPassword = false,
      _policies = false,
      _parent = false;
  String? _age, _message;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_signup &&
        (!_policies || _age == null || (_age == '16_17' && !_parent))) {
      setState(
        () => _message = 'Select your age range and accept the account terms. Ages 16–17 also require parent or guardian permission.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final signedIn = await widget.auth.authenticate(
        email: _email.text,
        password: _password.text,
        signup: _signup,
        ageBand: _age,
        acceptedPolicies: _policies,
        parentPermission: _parent,
      );
      if (!signedIn && mounted) {
        setState(() {
          _signup = false;
          _message =
              'Check your email to confirm your account, then sign in here.';
        });
      }
    } on BrainAuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.existingAccount
              ? existingKorlixAccountMessage
              : error.message;
          if (error.existingAccount) _signup = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Sign-in could not finish. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (!_email.text.trim().contains('@')) {
      setState(() => _message = 'Enter your account email address first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.auth.requestPasswordReset(_email.text);
      if (mounted) {
        setState(
          () => _message = 'If this email has a KORLIX account, password reset instructions will be sent.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not request a reset. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/branding/brain-icon-1024.png',
                      height: 124,
                      semanticLabel:
                          'KORLIX purple, red, green and gold emblem',
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'KORLIX',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w700,
                        color: brainGold,
                      ),
                    ),
                    const Text(
                      'BRAIN+VOICE',
                      textAlign: TextAlign.center,
                      style: TextStyle(letterSpacing: 4, fontSize: 16),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Your voice. Your brain.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 23),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Use the same email and password as KORLIX AI. Your approved memories and behaviors connect to Rici.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) =>
                          v != null &&
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v.trim())
                          ? null
                          : 'Enter a valid email address.',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: !_showPassword,
                      autofillHints: [
                        _signup
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter your password.'
                          : _signup && v.length < 8
                          ? 'Use at least 8 characters.'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_signup) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _age,
                        decoration: const InputDecoration(
                          labelText: 'Age range',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '18_plus',
                            child: Text('18 or older'),
                          ),
                          DropdownMenuItem(
                            value: '16_17',
                            child: Text('16–17'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _age = v),
                      ),
                      if (_age == '16_17')
                        CheckboxListTile(
                          value: _parent,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _parent = v!),
                          title: const Text(
                            'I have parent or guardian permission.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      CheckboxListTile(
                        value: _policies,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _policies = v!),
                        title: const Text(
                          'I agree to the Terms and acknowledge the Privacy Policy.',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Text(
                        'Available to ages 16+. New accounts start on Basic. Voice and document analysis use your account allowance.',
                      ),
                    ],
                    if (_message != null || widget.auth.restoreError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _message ?? 'Your saved sign-in could not be restored. Please sign in again.',
                            style: const TextStyle(color: brainGold),
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _busy
                              ? 'Please wait…'
                              : _signup
                              ? 'Create account'
                              : 'Sign in',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _signup = !_signup;
                              _message = null;
                            }),
                      child: Text(
                        _signup
                            ? 'Already have an account? Sign in'
                            : 'Create a KORLIX account',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _reset,
                      child: const Text('Forgot password?'),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://www.korlixdeveloper.com/terms.html',
                            ),
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
                    const Text(
                      'Version 1.0.0 · Build 1',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
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
