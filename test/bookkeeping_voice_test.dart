import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_voice.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_voice_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _businessId = '11111111-1111-4111-8111-111111111111';
const _otherId = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> _context() => {
  'business': {
    'id': _businessId,
    'name': 'Harbor Creative',
    'currency': 'USD',
    'basis': 'cash',
  },
  'month': '2026-10',
  'from_date': '2026-10-01',
  'as_of': '2026-10-31',
  'summary': {
    'income_cents': '10000',
    'expense_cents': '12500',
    'net_cents': '-2500',
  },
  'categories': [
    {
      'code': '4000',
      'name': 'Services',
      'kind': 'income',
      'amount_cents': '10000',
    },
    {
      'code': '5010',
      'name': 'Software',
      'kind': 'expense',
      'amount_cents': '12500',
    },
  ],
  'cash_accounts': [
    {'code': '1000', 'name': 'Recorded cash control'},
  ],
  'warnings': ['Recorded entries only.'],
};
Map<String, dynamic> _args() => {
  'kind': 'expense',
  'amount': '12.5',
  'entry_date': '2026-10-01',
  'category': '5010',
  'cash_account': '1000',
  'purpose': '  Design software  ',
  'counterparty': '  Creative Vendor  ',
  'receipt_reference': 'INV-15',
};
Map<String, dynamic> _draft([Map<String, dynamic>? args]) {
  final input = args ?? _args();
  return {
    'saved': false,
    'review_required': true,
    'draft': {
      ...input,
      'business_id': _businessId,
      'amount': '12.50',
      'purpose': '${input['purpose']}'.trim(),
      'counterparty': '${input['counterparty'] ?? ''}'.trim(),
      'receipt_reference': '${input['receipt_reference'] ?? ''}'.trim(),
    },
  };
}

http.Response _reply(dynamic body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
BookkeepingClient _client(
  Future<http.Response> Function(http.Request) handler, {
  Listenable? changes,
  Map<String, String> Function()? headers,
}) => BookkeepingClient(
  backendBaseUrl: 'https://fixture.test',
  headersBuilder: headers ?? () => {'Authorization': 'Bearer fixture'},
  sessionChanges: changes,
  client: MockClient(handler),
);
BookkeepingVoiceController _voice(BookkeepingClient client) {
  final voice = BookkeepingVoiceController(
    client: client,
    businessId: _businessId,
    businessName: 'Harbor Creative',
    month: '2026-10',
  );
  addTearDown(() {
    voice.dispose();
    client.dispose();
  });
  return voice;
}

Future<Map<String, dynamic>> _load(
  BookkeepingVoiceController voice, [
  String callId = 'context',
]) => voice.handleToolCall('get_bookkeeping_context', {}, callId);
Future<Map<String, dynamic>> _prepare(
  BookkeepingVoiceController voice, [
  String callId = 'draft',
]) => voice.handleToolCall('prepare_bookkeeping_entry', _args(), callId);
String _token(String user) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'fixture', 'sub': user, 'session_id': 'session-$user'}))).replaceAll('=', '')}.sig';

void main() {
  test(
    'only completed allowlisted read/draft calls are exposed; no save tool',
    () {
      expect(bookkeepingVoiceTools.map((t) => t['name']), [
        'get_bookkeeping_context',
        'prepare_bookkeeping_entry',
      ]);
      final response = {
        'status': 'completed',
        'output': [
          {
            'type': 'function_call',
            'status': 'completed',
            'name': 'get_bookkeeping_context',
            'call_id': 'read',
          },
          {
            'type': 'function_call',
            'status': 'completed',
            'name': 'save_bookkeeping_entry',
            'call_id': 'write',
          },
          {
            'type': 'function_call',
            'status': 'in_progress',
            'name': 'prepare_bookkeeping_entry',
            'call_id': 'draft',
          },
          {
            'type': 'function_call',
            'status': 'completed',
            'name': 'prepare_bookkeeping_entry',
            'call_id': '  ',
          },
        ],
      };
      expect(bookkeepingVoiceCalls(response).map((v) => v['call_id']), [
        'read',
      ]);
      expect(
        bookkeepingVoiceCalls({...response, 'status': 'cancelled'}),
        isEmpty,
      );
      expect(
        bookkeepingVoiceCalls({'status': 'completed', 'output': 'bad'}),
        isEmpty,
      );
    },
  );

  test(
    'context binds business and month; allowlist drops unrelated owner records and freezes totals',
    () async {
      final sent = <http.Request>[];
      final voice = _voice(
        _client((request) async {
          sent.add(request);
          return _reply({
            ..._context(),
            'owner_email': 'private@example.test',
            'entries': [
              {'purpose': 'unrelated'},
            ],
          });
        }),
      );
      final result = await _load(voice);
      expect(sent.single.method, 'GET');
      expect(
        sent.single.url.path,
        '/api/bookkeeping/businesses/$_businessId/voice/context',
      );
      expect(sent.single.url.queryParameters, {'month': '2026-10'});
      expect(result['summary']['net_cents'], '-2500');
      expect(result.containsKey('owner_email'), false);
      expect(result.containsKey('entries'), false);
      expect(
        () => result['summary']['net_cents'] = '0',
        throwsUnsupportedError,
      );
      expect(() => voice.context['categories'].add({}), throwsUnsupportedError);
      expect(
        (await voice.handleToolCall('get_bookkeeping_context', {
          'business_id': _otherId,
        }, 'wrong'))['success'],
        false,
      );
      expect(
        (await voice.handleToolCall('get_bookkeeping_context', {
          'month': '2025-01',
        }, 'wrong-month'))['success'],
        false,
      );
      expect(sent, hasLength(1));
    },
  );

  test(
    'malformed totals, foreign scope and non-USD context fail without displaying zero',
    () async {
      final bad = <Map<String, dynamic>>[
        {
          ..._context(),
          'summary': {
            'income_cents': null,
            'expense_cents': '12500',
            'net_cents': '-2500',
          },
        },
        {
          ..._context(),
          'summary': {
            'income_cents': '100.00',
            'expense_cents': '12500',
            'net_cents': '-2500',
          },
        },
        {
          ..._context(),
          'business': {..._context()['business'], 'id': _otherId},
        },
        {
          ..._context(),
          'business': {..._context()['business'], 'currency': 'CAD'},
        },
        {..._context(), 'month': '2026-09'},
        {
          ..._context(),
          'categories': [
            {'code': '5010', 'name': 'Software', 'kind': 'expense'},
          ],
        },
      ];
      for (var index = 0; index < bad.length; index++) {
        final voice = _voice(_client((request) async => _reply(bad[index])));
        expect((await _load(voice))['success'], false);
        expect(voice.context, isEmpty);
        expect(voice.result.containsKey('summary'), false);
        expect(voice.pendingDraft, isNull);
      }
    },
  );

  test(
    'draft requires real context and exact validated known fields',
    () async {
      final sent = <http.Request>[];
      final voice = _voice(
        _client((request) async {
          sent.add(request);
          return _reply(_context());
        }),
      );
      expect((await _prepare(voice))['success'], false);
      expect(sent, isEmpty);
      await _load(voice);
      final invalid = <dynamic>[
        {..._args(), 'kind': 'transfer'},
        {..._args(), 'amount': 12.5},
        {..._args(), 'amount': '0'},
        {..._args(), 'amount': '12.501'},
        {..._args(), 'entry_date': '2026-02-30'},
        {..._args(), 'category': '4000'},
        {..._args(), 'cash_account': '1001'},
        {..._args(), 'purpose': ''},
        {..._args(), 'business_id': _otherId},
        {..._args(), 'confirmed': true},
        {..._args(), 'currency': 'CAD'},
        {..._args()}..remove('entry_date'),
        {'kind': 'income'},
        'invalid JSON',
        null,
      ];
      for (var i = 0; i < invalid.length; i++) {
        expect(
          (await voice.handleToolCall(
            'prepare_bookkeeping_entry',
            invalid[i],
            'invalid-$i',
          ))['success'],
          false,
        );
      }
      expect(
        (await voice.handleToolCall(
          'save_bookkeeping_entry',
          {},
          'save',
        ))['success'],
        false,
      );
      expect(sent, hasLength(1));
      expect(voice.pendingDraft, isNull);
    },
  );

  test(
    'draft preparation is scoped, unsaved and immutable; duplicate IDs issue one request',
    () async {
      final sent = <http.Request>[];
      final held = Completer<http.Response>();
      final voice = _voice(
        _client((request) async {
          sent.add(request);
          return request.method == 'GET' ? _reply(_context()) : held.future;
        }),
      );
      await _load(voice);
      final first = _prepare(voice);
      final duplicate = voice.handleToolCall(
        'prepare_bookkeeping_entry',
        jsonEncode(_args()),
        'draft',
      );
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(2));
      expect(
        (await voice.handleToolCall('prepare_bookkeeping_entry', {
          ..._args(),
          'amount': '17.50',
        }, 'draft'))['success'],
        false,
      );
      held.complete(_reply(_draft()));
      final results = await Future.wait([first, duplicate]);
      expect(
        results.every(
          (r) => r['saved'] == false && r['review_required'] == true,
        ),
        true,
      );
      expect(
        sent.last.url.path,
        '/api/bookkeeping/businesses/$_businessId/voice/draft',
      );
      expect(jsonDecode(sent.last.body), _args());
      expect(voice.pendingDraft!['business_id'], _businessId);
      expect(voice.pendingDraft!['amount'], '12.50');
      expect(voice.pendingDraft!['purpose'], 'Design software');
      expect(
        () => voice.pendingDraft!['amount'] = '1.00',
        throwsUnsupportedError,
      );
      await _prepare(voice);
      expect(sent, hasLength(2));
    },
  );

  test(
    'mismatched or already-saved responses cannot become reviewable drafts',
    () async {
      for (final change in [
        'business',
        'amount',
        'purpose',
        'saved',
        'review',
      ]) {
        final response = _draft();
        if (change == 'business') response['draft']['business_id'] = _otherId;
        if (change == 'amount') response['draft']['amount'] = '13.00';
        if (change == 'purpose')
          response['draft']['purpose'] = 'Different purpose';
        if (change == 'saved') response['saved'] = true;
        if (change == 'review') response['review_required'] = false;
        final voice = _voice(
          _client(
            (request) async =>
                _reply(request.method == 'GET' ? _context() : response),
          ),
        );
        await _load(voice);
        expect((await _prepare(voice))['success'], false);
        expect(voice.pendingDraft, isNull);
      }
    },
  );

  test(
    'optional unspecified party/reference are empty and never inferred',
    () async {
      final args = _args()
        ..remove('counterparty')
        ..remove('receipt_reference');
      final voice = _voice(
        _client(
          (request) async =>
              _reply(request.method == 'GET' ? _context() : _draft(args)),
        ),
      );
      await _load(voice);
      expect(
        (await voice.handleToolCall(
          'prepare_bookkeeping_entry',
          args,
          'draft',
        ))['success'],
        true,
      );
      expect(voice.pendingDraft!['counterparty'], '');
      expect(voice.pendingDraft!['receipt_reference'], '');
    },
  );

  test(
    'pause clears data and discards late draft without replaying the old call',
    () async {
      final sent = <http.Request>[];
      final held = Completer<http.Response>();
      final voice = _voice(
        _client((request) async {
          sent.add(request);
          return request.method == 'GET' ? _reply(_context()) : held.future;
        }),
      );
      await _load(voice);
      final pending = _prepare(voice);
      await Future<void>.delayed(Duration.zero);
      voice.clearPending();
      held.complete(_reply(_draft()));
      expect((await pending)['discarded'], true);
      expect(voice.result, isEmpty);
      expect(voice.context, isEmpty);
      expect(voice.pendingDraft, isNull);
      expect(voice.busy, false);
      expect((await _prepare(voice))['discarded'], true);
      expect(sent, hasLength(2));
    },
  );

  test(
    'access denial clears context and draft; all future requests are unavailable',
    () async {
      var requests = 0;
      final voice = _voice(
        _client((request) async {
          requests++;
          if (requests > 2) return _reply({'error': 'denied'}, 403);
          return _reply(request.method == 'GET' ? _context() : _draft());
        }),
      );
      await _load(voice);
      await _prepare(voice);
      expect(voice.pendingDraft, isNotNull);
      expect((await _load(voice, 'denied'))['discarded'], true);
      expect(voice.available, false);
      expect(voice.context, isEmpty);
      expect(voice.result, isEmpty);
      expect(voice.pendingDraft, isNull);
      expect((await _load(voice, 'again'))['discarded'], true);
      expect(requests, 3);
    },
  );

  test(
    'session switch during pending work cannot disclose its late result',
    () async {
      final changes = ChangeNotifier();
      addTearDown(changes.dispose);
      var user = 'one';
      final held = Completer<http.Response>();
      final voice = _voice(
        _client(
          (request) async =>
              request.method == 'GET' ? _reply(_context()) : held.future,
          changes: changes,
          headers: () => {'Authorization': 'Bearer ${_token(user)}'},
        ),
      );
      await _load(voice);
      final pending = _prepare(voice);
      await Future<void>.delayed(Duration.zero);
      user = 'two';
      changes.notifyListeners();
      held.complete(_reply(_draft()));
      expect((await pending)['discarded'], true);
      expect(voice.available, false);
      expect(voice.context, isEmpty);
      expect(voice.pendingDraft, isNull);
    },
  );

  test(
    'bounded tool requests cannot be reset into an unlimited loop by pausing',
    () async {
      var requests = 0;
      final voice = _voice(
        _client((request) async {
          requests++;
          return _reply(_context());
        }),
      );
      for (var i = 0; i < 64; i++) {
        expect((await _load(voice, 'context-$i'))['success'], true);
        voice.clearPending();
      }
      expect((await _load(voice, 'extra'))['success'], false);
      expect(requests, 64);
    },
  );

  testWidgets(
    'panel shows exact draft, selected scope and totals; review itself never writes',
    (tester) async {
      final sent = <http.Request>[];
      var reviewed = false;
      final voice = _voice(
        _client((request) async {
          sent.add(request);
          return _reply(request.method == 'GET' ? _context() : _draft());
        }),
      );
      await _load(voice);
      await _prepare(voice);
      await tester.binding.setSurfaceSize(const Size(390, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BookkeepingVoicePanel(
                controller: voice,
                onReview: () async {
                  reviewed = true;
                },
                onDismiss: voice.clearPending,
              ),
            ),
          ),
        ),
      );
      for (final text in [
        'Reporting month: 2026-10 · USD',
        'Draft only · Not saved',
        r'Recorded income: $100.00',
        r'Recorded expenses: $125.00',
        r'Recorded net: -$25.00',
        r'Amount: $12.50 USD',
        'Date received / paid: 2026-10-01',
        'Category: Software (5010)',
        'Cash account: Recorded cash control (1000)',
        'Business purpose: Design software',
        'Customer / vendor: Creative Vendor',
        'Receipt reference: INV-15',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Review entry'));
      await tester.tap(find.text('Review entry'));
      expect(reviewed, true);
      expect(
        sent
            .map((r) => r.url.path)
            .every(
              (path) => path.endsWith('/context') || path.endsWith('/draft'),
            ),
        true,
      );
      expect(sent, hasLength(2));
      await tester.tap(find.text('Dismiss draft'));
      await tester.pump();
      expect(find.text('Draft only · Not saved'), findsNothing);
    },
  );
}
