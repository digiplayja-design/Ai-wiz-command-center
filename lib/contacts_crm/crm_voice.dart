import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'contacts_client.dart';

Map<String, dynamic> _text([int max = 2000]) => {
  'type': 'string',
  'maxLength': max,
};
Map<String, dynamic> _tool(String name, String description, CrmJson fields) => {
  'type': 'function',
  'name': name,
  'description': description,
  'parameters': {
    'type': 'object',
    'properties': fields,
    'required': fields.keys.toList(),
    'additionalProperties': false,
  },
};
final crmVoiceTools = <CrmJson>[
  _tool(
    'get_crm_context',
    'Read your CRM contacts, current date and supported actions.',
    {},
  ),
  _tool(
    'search_crm_contacts',
    'Search your own contacts. Empty query lists contacts. Segment follow_up means due follow-ups; email_ready means contacts with email permission.',
    {
      'query': _text(100),
      'segment': {
        'type': 'string',
        'enum': ['', 'follow_up', 'email_ready'],
      },
    },
  ),
  _tool(
    'get_crm_contact',
    'Read one contact previously returned by context or search.',
    {'contact_id': _text(36)},
  ),
  _tool(
    'draft_crm_note',
    'Prepare an UNSAVED note appended to existing notes, and/or a follow-up calendar date YYYY-MM-DD. Empty date preserves the current date. Clarify ambiguous dates.',
    {'contact_id': _text(36), 'note': _text(2000), 'follow_up_on': _text(10)},
  ),
  _tool(
    'draft_crm_email',
    'Prepare an UNSAVED transactional follow-up email for a returned contact with recorded email permission. Never send or enable rules.',
    {'contact_id': _text(36), 'subject': _text(200), 'body': _text(6000)},
  ),
];
List<CrmJson> crmVoiceCalls(dynamic response) {
  if (response is! Map ||
      response['status'] != 'completed' ||
      response['output'] is! List) {
    return [];
  }
  final names = crmVoiceTools.map((t) => t['name']).toSet();
  return (response['output'] as List)
      .whereType<Map>()
      .where(
        (x) =>
            x['type'] == 'function_call' &&
            x['status'] == 'completed' &&
            names.contains(x['name']) &&
            x['call_id'] is String &&
            (x['call_id'] as String).trim().isNotEmpty,
      )
      .take(16)
      .map((x) => Map<String, dynamic>.from(x))
      .toList();
}

class CrmVoiceController extends ChangeNotifier {
  CrmVoiceController({required this.client}) {
    client.addAccessDeniedListener(_accessDenied);
  }
  final ContactsClient client;
  bool _closed = false, _revoked = false, _busy = false;
  int _epoch = 0, _count = 0;
  CrmJson _result = {}, _context = {};
  CrmJson? _pending;
  final _contacts = <String, int>{};
  final _retired = <String>{};
  final _calls =
      <String, ({String fingerprint, int epoch, Future<CrmJson> future})>{};
  bool get available => !_closed && !_revoked && !client.sessionChanged;
  bool get busy => available && _busy;
  CrmJson get result => crmClone(available ? _result : {});
  CrmJson get context => crmClone(available ? _context : {});
  CrmJson? get pendingDraft =>
      available && _pending != null ? crmClone(_pending!) : null;
  CrmJson? get pendingOpen => null;
  bool _current(int epoch) => available && epoch == _epoch;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _accessDenied() {
    _revoked = true;
    clearPending();
  }

  static CrmJson _discarded() => {
    'success': false,
    'discarded': true,
    'saved': false,
    'message':
        'This CRM voice request is no longer active. Do not read stale results.',
  };
  static CrmJson _error(Object e) => {
    'success': false,
    'saved': false,
    'message': e is ContactsException
        ? e.message
        : 'CRM could not verify this request. Please ask again with clear details.',
  };
  void clearPending() {
    if (_closed) return;
    _epoch++;
    _busy = false;
    _result = {};
    _context = {};
    _pending = null;
    _contacts.clear();
    _retired.addAll(_calls.keys);
    _calls.clear();
    _notify();
  }

  CrmJson _arguments(String name, dynamic raw) {
    final encoded = raw is String ? raw : jsonEncode(raw);
    if (encoded.length > 12000) {
      throw const ContactsException('Shorten this voice request.');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const ContactsException('Use supported request fields.');
    }
    final args = Map<String, dynamic>.from(decoded),
        schema = crmVoiceTools.where((t) => t['name'] == name).firstOrNull;
    if (schema == null) {
      throw const ContactsException('That CRM voice tool is unavailable.');
    }
    final fields = crmMap(crmMap(schema['parameters'])['properties']);
    if (args.length != fields.length ||
        args.keys.any((k) => !fields.containsKey(k))) {
      throw const ContactsException('Use only the supported request fields.');
    }
    for (final e in fields.entries) {
      final spec = crmMap(e.value), v = args[e.key];
      if (spec['type'] == 'integer') {
        if (v is! int || v < 0 || v > 100000) {
          throw const ContactsException(
            'Use a whole number of newly completed units.',
          );
        }
      } else if (v is! String ||
          v.length > (spec['maxLength'] as int? ?? 2000) ||
          (spec['enum'] is List && !(spec['enum'] as List).contains(v))) {
        throw const ContactsException('Use valid CRM field values.');
      }
    }
    if (name != 'get_crm_context' && _context.isEmpty) {
      throw const ContactsException('Read get_crm_context first.');
    }
    if (args['contact_id'] != null &&
        !_contacts.containsKey(args['contact_id'])) {
      throw const ContactsException(
        'Choose a contact returned by CRM context or search.',
      );
    }
    return args;
  }

  Future<CrmJson> handleToolCall(String name, dynamic raw, String callId) {
    try {
      if (!available || _retired.contains(callId)) {
        return Future.value(_discarded());
      }
      final args = _arguments(name, raw), keys = args.keys.toList()..sort();
      final fingerprint =
          '$name:${jsonEncode({for (final k in keys) k: args[k]})}';
      final prior = _calls[callId];
      if (prior != null) {
        return prior.epoch != _epoch
            ? Future.value(_discarded())
            : prior.fingerprint == fingerprint
            ? prior.future
            : Future.value(
                _error(
                  const ContactsException(
                    'A repeated request changed. Ask again.',
                  ),
                ),
              );
      }
      if (callId.trim().isEmpty || callId.length > 200 || _count >= 64) {
        throw const ContactsException(
          'Close voice and reopen it from CRM before another request.',
        );
      }
      if (_busy) {
        throw const ContactsException('Wait for the current CRM request.');
      }
      _count++;
      final epoch = _epoch, future = _execute(name, args, epoch);
      _calls[callId] = (fingerprint: fingerprint, epoch: epoch, future: future);
      return future;
    } catch (e) {
      return Future.value(_error(e));
    }
  }

  Future<CrmJson> _execute(String name, CrmJson args, int epoch) async {
    _busy = true;
    _result = {};
    _notify();
    try {
      if (name == 'get_crm_context' ||
          name == 'search_crm_contacts' ||
          name == 'get_crm_contact') {
        final r = await client.request(
          'GET',
          '/voice/context',
          query: name == 'search_crm_contacts'
              ? {'q': args['query'], 'segment': args['segment']}
              : name == 'get_crm_contact'
              ? {'contact_id': args['contact_id']}
              : null,
        );
        if (!_current(epoch)) return _discarded();
        for (final c in crmRows(r['contacts'])) {
          if (c['id'] is String && c['version'] is int) {
            _contacts[c['id']] = c['version'];
          }
        }
        _context = crmClone(r);
        _result = {...r, 'kind': 'context', 'saved': false};
      } else {
        _pending = null;
        final action = name == 'draft_crm_note'
            ? 'note'
            : name == 'draft_crm_email'
            ? 'email'
            : throw const ContactsException('Unsupported draft.');
        final contactId = args['contact_id'] as String,
            version = _contacts[contactId];
        final r = await client.request(
          'POST',
          '/voice/draft',
          body: {
            'action': action,
            'contact_id': contactId,
            'version': version,
            'payload': {
              for (final e in args.entries)
                if (e.key != 'contact_id') e.key: e.value,
            },
          },
        );
        if (!_current(epoch)) return _discarded();
        if (r['saved'] != false ||
            r['reviewRequired'] != true ||
            r['contact_id'] != contactId ||
            r['contact_version'] != version ||
            r['action'] != action ||
            r['draft'] is! Map) {
          throw const ContactsException(
            'This draft could not be verified. Reopen CRM.',
          );
        }
        _pending = crmClone(r);
        _result = {
          ...r,
          'kind': 'draft',
          'message':
              'Unsaved draft ready. Tap Review in CRM, inspect the fields and save there.',
        };
      }
      if (!_current(epoch)) return _discarded();
      _notify();
      return result;
    } catch (e) {
      if (e is ContactsException && [401, 403, 409].contains(e.status)) {
        _accessDenied();
      }
      if (!_current(epoch)) return _discarded();
      _result = _error(e);
      _notify();
      return result;
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    client.removeAccessDeniedListener(_accessDenied);
    _closed = true;
    _epoch++;
    _calls.clear();
    _retired.clear();
    _contacts.clear();
    _pending = null;
    _context = {};
    _result = {};
    super.dispose();
  }
}
