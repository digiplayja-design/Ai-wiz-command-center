import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'workforce_client.dart';

Map<String, dynamic> _text([int max = 2000]) => {
  'type': 'string',
  'maxLength': max,
};
Map<String, dynamic> _tool(String name, String description, WfJson fields) => {
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
final workforceVoiceTools = <WfJson>[
  _tool(
    'get_workforce_context',
    'Read the current company, your role, current date/timezone, team records and available draft actions.',
    {},
  ),
  _tool(
    'search_workforce_records',
    'Search only authorized records in the current workspace. Results and date windows may be incomplete.',
    {
      'category': {
        'type': 'string',
        'enum': ['tasks', 'members', 'schedule', 'updates'],
      },
      'query': _text(120),
    },
  ),
  _tool(
    'draft_workforce_task',
    'Prepare a new UNSAVED task. Use a returned active member ID (ordinary members may use only themselves). Use an explicit UTC offset for due_at or empty for no deadline. Ask for missing assignment/title details.',
    {
      'title': _text(160),
      'details': _text(2000),
      'assignee_id': _text(36),
      'priority': {
        'type': 'string',
        'enum': ['low', 'normal', 'high', 'urgent'],
      },
      'project': _text(100),
      'worksite': _text(100),
      'due_at': _text(40),
    },
  ),
  _tool(
    'draft_workforce_schedule',
    'Managers only: prepare an UNSAVED shift for a returned active member. Clarify exact date, time and timezone; timestamps need an explicit UTC offset. Maximum 24 hours.',
    {
      'user_id': _text(36),
      'starts_at': _text(40),
      'ends_at': _text(40),
      'worksite': _text(100),
      'notes': _text(1000),
    },
  ),
  _tool(
    'draft_workforce_update',
    'Prepare your own UNSAVED work update for an actual returned current/recent shift. Quantity is only newly completed units, not the day total.',
    {
      'shift_id': _text(36),
      'summary': _text(2000),
      'quantity': {'type': 'integer', 'minimum': 0, 'maximum': 100000},
      'project': _text(100),
      'blockers': _text(1000),
    },
  ),
];
List<WfJson> workforceVoiceCalls(dynamic response) {
  if (response is! Map ||
      response['status'] != 'completed' ||
      response['output'] is! List) {
    return [];
  }
  final names = workforceVoiceTools.map((t) => t['name']).toSet();
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

class WorkforceVoiceController extends ChangeNotifier {
  WorkforceVoiceController({
    required this.client,
    required this.organizationId,
    required this.memberId,
    required this.memberVersion,
  }) {
    client.addAccessDeniedListener(_accessDenied);
  }
  final WorkforceClient client;
  final String organizationId, memberId;
  final int memberVersion;
  bool _closed = false, _revoked = false, _busy = false;
  int _epoch = 0, _count = 0;
  WfJson _result = {}, _context = {};
  WfJson? _pending;
  final _members = <String>{}, _shifts = <String>{}, _retired = <String>{};
  final _calls =
      <String, ({String fingerprint, int epoch, Future<WfJson> future})>{};
  bool get available => !_closed && !_revoked && !client.sessionChanged;
  bool get busy => available && _busy;
  WfJson get result => wfClone(available ? _result : {});
  WfJson get context => wfClone(available ? _context : {});
  WfJson? get pendingDraft =>
      available && _pending != null ? wfClone(_pending!) : null;
  WfJson? get pendingOpen => null;
  bool _current(int epoch) => available && epoch == _epoch;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _accessDenied() {
    _revoked = true;
    clearPending();
  }

  static WfJson _discarded() => {
    'success': false,
    'discarded': true,
    'saved': false,
    'message':
        'This Workforce voice request is no longer active. Do not read stale results.',
  };
  static WfJson _error(Object e) => {
    'success': false,
    'saved': false,
    'message': e is WorkforceException
        ? e.message
        : 'Workforce could not verify this request. Please ask again with clear details.',
  };
  void clearPending() {
    if (_closed) return;
    _epoch++;
    _busy = false;
    _result = {};
    _context = {};
    _pending = null;
    _members.clear();
    _shifts.clear();
    _retired.addAll(_calls.keys);
    _calls.clear();
    _notify();
  }

  WfJson _arguments(String name, dynamic raw) {
    final encoded = raw is String ? raw : jsonEncode(raw);
    if (encoded.length > 12000) {
      throw const WorkforceException('Shorten this voice request.');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const WorkforceException('Use supported request fields.');
    }
    final args = Map<String, dynamic>.from(decoded),
        schema = workforceVoiceTools
            .where((t) => t['name'] == name)
            .firstOrNull;
    if (schema == null) {
      throw const WorkforceException(
        'That Workforce voice tool is unavailable.',
      );
    }
    final fields = wfMap(wfMap(schema['parameters'])['properties']);
    if (args.length != fields.length ||
        args.keys.any((k) => !fields.containsKey(k))) {
      throw const WorkforceException('Use only the supported request fields.');
    }
    for (final e in fields.entries) {
      final spec = wfMap(e.value), v = args[e.key];
      if (spec['type'] == 'integer') {
        if (v is! int || v < 0 || v > 100000) {
          throw const WorkforceException(
            'Use a whole number of newly completed units.',
          );
        }
      } else if (v is! String ||
          v.length > (spec['maxLength'] as int? ?? 2000) ||
          (spec['enum'] is List && !(spec['enum'] as List).contains(v))) {
        throw const WorkforceException('Use valid Workforce field values.');
      }
    }
    if (name != 'get_workforce_context' && _context.isEmpty) {
      throw const WorkforceException('Read get_workforce_context first.');
    }
    final person = args['assignee_id'] ?? args['user_id'];
    if (person != null && !_members.contains(person)) {
      throw const WorkforceException(
        'Choose a real member returned by Workforce context or search.',
      );
    }
    if (args['shift_id'] != null && !_shifts.contains(args['shift_id'])) {
      throw const WorkforceException(
        'Choose your shift returned by Workforce context.',
      );
    }
    return args;
  }

  Future<WfJson> handleToolCall(String name, dynamic raw, String callId) {
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
                  const WorkforceException(
                    'A repeated request changed. Ask again.',
                  ),
                ),
              );
      }
      if (callId.trim().isEmpty || callId.length > 200 || _count >= 64) {
        throw const WorkforceException(
          'Close voice and reopen it from Workforce before another request.',
        );
      }
      if (_busy) {
        throw const WorkforceException(
          'Wait for the current Workforce request.',
        );
      }
      _count++;
      final epoch = _epoch, future = _execute(name, args, epoch);
      _calls[callId] = (fingerprint: fingerprint, epoch: epoch, future: future);
      return future;
    } catch (e) {
      return Future.value(_error(e));
    }
  }

  Future<WfJson> _execute(String name, WfJson args, int epoch) async {
    _busy = true;
    _result = {};
    _notify();
    try {
      if (name == 'get_workforce_context' ||
          name == 'search_workforce_records') {
        final r = await client.request(
          'GET',
          '/$organizationId/voice/context',
          query: name == 'search_workforce_records'
              ? {'category': args['category'], 'query': args['query']}
              : null,
        );
        if (!_current(epoch)) return _discarded();
        final member = wfMap(r['member']);
        if (wfMap(r['organization'])['id'] != organizationId ||
            member['user_id'] != memberId ||
            member['version'] != memberVersion) {
          _accessDenied();
          return _discarded();
        }
        for (final m in wfRows(r['members'])) {
          if (m['active'] == true) _members.add(m['user_id'] as String);
        }
        _shifts.clear();
        for (final shift in wfRows(r['own_shifts'])) {
          _shifts.add(shift['id'] as String);
        }
        _context = wfClone(r);
        _result = {...r, 'kind': 'context', 'saved': false};
      } else {
        _pending = null;
        final action = switch (name) {
          'draft_workforce_task' => 'task_create',
          'draft_workforce_schedule' => 'schedule',
          'draft_workforce_update' => 'update',
          _ => throw const WorkforceException('Unsupported draft.'),
        };
        final r = await client.request(
          'POST',
          '/$organizationId/voice/draft',
          body: {
            'action': action,
            'payload': args,
            'member_version': memberVersion,
          },
        );
        if (!_current(epoch)) return _discarded();
        if (r['saved'] != false ||
            r['reviewRequired'] != true ||
            r['organization_id'] != organizationId ||
            r['member_id'] != memberId ||
            r['member_version'] != memberVersion ||
            r['action'] != action ||
            r['draft'] is! Map) {
          throw const WorkforceException(
            'The draft could not be verified. Reopen Workforce.',
          );
        }
        _pending = wfClone(r);
        _result = {
          ...r,
          'kind': 'draft',
          'message':
              'Unsaved draft ready. Tap Review in Workforce, inspect the fields and save there.',
        };
      }
      if (!_current(epoch)) return _discarded();
      _notify();
      return result;
    } catch (e) {
      if (e is WorkforceException && [401, 403, 409].contains(e.status)) {
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
    _members.clear();
    _shifts.clear();
    _pending = null;
    _context = {};
    _result = {};
    super.dispose();
  }
}
