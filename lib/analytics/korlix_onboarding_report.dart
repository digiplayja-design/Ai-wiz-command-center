import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class KorlixOnboardingReport extends StatefulWidget {
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  const KorlixOnboardingReport({
    super.key,
    required this.baseUrl,
    required this.headersBuilder,
  });
  @override
  State<KorlixOnboardingReport> createState() => _KorlixOnboardingReportState();
}

class _KorlixOnboardingReportState extends State<KorlixOnboardingReport> {
  int _days = 7;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse(
              '${widget.baseUrl}/api/admin/onboarding/summary?days=$_days&platform=android',
            ),
            headers: widget.headersBuilder(),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 403) {
        throw Exception('This report is limited to authorized administrators.');
      }
      if (response.statusCode != 200) {
        throw Exception(
          'The report is not available yet. Check the backend deployment and try again.',
        );
      }
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      if (mounted) setState(() => _data = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _rows(
    String title,
    Map<String, dynamic> values,
    Map<String, String> labels,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final label in labels.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(label.value)),
                    Text('${values[label.key] ?? 0}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    Map<String, dynamic> section(String key) =>
        Map<String, dynamic>.from(data?[key] as Map? ?? {});
    return Scaffold(
      appBar: AppBar(title: const Text('New user journey')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Android app activity • All acquisition sources'),
          Wrap(
            spacing: 8,
            children: [
              for (final days in [1, 7, 30])
                ChoiceChip(
                  label: Text('Last $days ${days == 1 ? 'day' : 'days'}'),
                  selected: _days == days,
                  onSelected: _loading
                      ? null
                      : (_) {
                          setState(() => _days = days);
                          _load();
                        },
                ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          if (data != null && !_loading && _error == null) ...[
            Text('Window: ${data['start']} to ${data['end']} (UTC)'),
            const SizedBox(height: 12),
            if (data['first_client_event_at'] == null)
              const Text(
                'No app-side measurements received yet. First-open and screen counts require the updated app.',
              ),
            _rows(
              'New app setups in this window',
              section('new_setup_cohort'),
              {
                'opened': 'Opened Korlix',
                'registration_screen': 'Viewed registration',
                'registration_submitted': 'Tapped Create account',
                'confirmation_screen': 'Saw email confirmation screen',
                'signed_in': 'Signed in successfully',
                'completed_ai_generation': 'Completed a saved AI generation',
              },
            ),
            const Text(
              'Fresh local app storage can include reinstalls or another device. Returning customers can skip registration. These counts are not Google Ads attribution.',
            ),
            _rows(
              'New accounts • All platforms and sources',
              section('new_accounts_all_platforms'),
              {
                'created': 'Accounts created',
                'email_confirmed': 'Email confirmed',
                'signed_in': 'Signed in',
                'completed_ai_generation': 'Completed a saved AI generation',
              },
            ),
            _rows(
              'Android authentication requests',
              section('authentication_events'),
              {
                'signup_attempt': 'Signup requests',
                'signup_accepted': 'Signup requests accepted',
                'signup_rejected': 'Signup requests rejected',
                'signin_attempt': 'Sign-in requests',
                'signin_rejected': 'Sign-in requests rejected',
                'sign_in_succeeded': 'Successful sign-ins',
              },
            ),
            const Text(
              'Accepted signup requests do not prove account creation or email confirmation. AI generation counts cover records saved in generation history; other features are not included.',
            ),
            _rows(
              'Registration problems • Event counts',
              section('registration_errors'),
              {
                'eligibility': 'Age or policy declaration',
                'required_fields': 'Missing required fields',
                'password_length': 'Password too short',
                'network': 'Network or timeout',
                'response': 'Unexpected response',
                'auth_rejected': 'Authentication rejected',
                'rate_limited': 'Too many requests',
                'server_error': 'Server error',
              },
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _loading ? null : _load,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
