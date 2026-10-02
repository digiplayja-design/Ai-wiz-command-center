import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'fieldproof_client.dart';
import 'fieldproof_report.dart';
import 'fieldproof_workspace.dart';

Map<String, dynamic> _tool(
  String name,
  String description,
  Map<String, dynamic> fields,
) => {
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
Map<String, dynamic> _str(int length) => {
  'type': 'string',
  'maxLength': length,
};
final fieldProofVoiceTools = <Map<String, dynamic>>[
  _tool(
    'get_fieldproof_context',
    'Read the current signed-in FieldProof workspace, actual templates and selected job before discussing it. No changes are saved.',
    {},
  ),
  _tool(
    'search_fieldproof_jobs',
    'Search actual jobs by title, customer, location, work order or asset. Results may be truncated. Never invent IDs.',
    {'query': _str(100)},
  ),
  _tool(
    'read_fieldproof_job',
    'Read a known job from context/search. This selects it for an unsaved draft and clears the previous draft. Photo metadata is not photo analysis.',
    {'job_id': _str(36)},
  ),
  _tool(
    'start_fieldproof_draft',
    'Start a NEW unsaved job with a template returned by context. Clears the current unsaved draft. Use only when the user requests a new job.',
    {'template': _str(40)},
  ),
  _tool(
    'update_fieldproof_field',
    'Update ONE requested field of the unsaved selected job. Read context first; start a draft for a new job. Preserve other values. Dates YYYY-MM-DD; hours numeric text or empty; priority low/normal/high/urgent; stage planned/in_progress/blocked/ready. Never invent values. User must Review in FieldProof and save.',
    {
      'field': {'type': 'string', 'enum': fpVoiceFields.keys.toList()},
      'value': _str(4000),
    },
  ),
  _tool(
    'add_fieldproof_reading',
    'Append an UNSAVED reading exactly as supplied. Preserve leading zeros, decimals and units. No estimates. Use empty unit/note when omitted.',
    {
      'label': _str(100),
      'value': _str(160),
      'unit': _str(40),
      'note': _str(350),
    },
  ),
  _tool(
    'add_fieldproof_issue',
    'Append an UNSAVED unresolved follow-up. Never claim anyone was notified. Empty assignee/date when omitted; blocking means it must be resolved before closeout.',
    {
      'label': _str(200),
      'assignee': _str(100),
      'dueOn': _str(10),
      'priority': {'type': 'string', 'enum': fpPriorities.keys.toList()},
      'blocking': {'type': 'boolean'},
    },
  ),
];
List<Map<String, dynamic>> fieldProofVoiceCalls(dynamic response) {
  if (response is! Map ||
      response['status'] != 'completed' ||
      response['output'] is! List) {
    return [];
  }
  final names = fieldProofVoiceTools.map((x) => x['name']).toSet();
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

class FieldProofVoiceController extends ChangeNotifier {
  FieldProofVoiceController({
    required this.client,
    Map<String, dynamic>? snapshot,
  }) : initialSnapshot = fpClone(snapshot ?? {}) {
    _selected = fpClone(initialSnapshot);
    client.addAccessDeniedListener(_accessDenied);
  }
  final FieldProofClient client;
  final Map<String, dynamic> initialSnapshot;
  bool _closed = false, _busy = false;
  int _epoch = 0, _count = 0;
  Map<String, dynamic> _result = {},
      _context = {},
      _templates = {},
      _selected = {};
  Map<String, dynamic>? _draft, _pendingDraft, _pendingOpen;
  final _known = <String, Map<String, dynamic>>{};
  final _retired = <String>{};
  final _calls =
      <
        String,
        ({String fingerprint, int epoch, Future<Map<String, dynamic>> future})
      >{};
  bool get available => !_closed && !client.sessionChanged;
  bool get busy => available && _busy;
  Map<String, dynamic> get result => fpClone(available ? _result : {});
  Map<String, dynamic> get context => fpClone(available ? _context : {});
  Map<String, dynamic>? get pendingDraft =>
      available && _pendingDraft != null ? fpClone(_pendingDraft!) : null;
  Map<String, dynamic>? get pendingOpen =>
      available && _pendingOpen != null ? fpClone(_pendingOpen!) : null;
  Map<String, dynamic> get _job => fpMap(_selected['job']);
  bool _current(int epoch) => available && epoch == _epoch;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _accessDenied() => clearPending();
  static Map<String, dynamic> _discarded() => {
    'success': false,
    'discarded': true,
    'saved': false,
    'message':
        'This FieldProof voice request is no longer active. Do not read stale results.',
  };
  static Map<String, dynamic> _error(Object e) => {
    'success': false,
    'saved': false,
    'message': e is FieldProofException
        ? e.message
        : 'FieldProof could not verify that request. Ask again with clear details.',
  };
  void clearPending() {
    if (_closed) return;
    _epoch++;
    _busy = false;
    _result = {};
    _context = {};
    _templates = {};
    _selected = fpClone(initialSnapshot);
    _draft = null;
    _pendingDraft = null;
    _pendingOpen = null;
    _known.clear();
    _retired.addAll(_calls.keys);
    _calls.clear();
    _notify();
  }

  Map<String, dynamic> _arguments(String name, dynamic raw) {
    final encoded = raw is String ? raw : jsonEncode(raw);
    if (encoded.length > 16000) {
      throw const FieldProofException('Shorten this voice request.');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FieldProofException('Use clear FieldProof request fields.');
    }
    final args = Map<String, dynamic>.from(decoded);
    final schema = fieldProofVoiceTools
        .where((x) => x['name'] == name)
        .firstOrNull;
    if (schema == null) {
      throw const FieldProofException(
        'That FieldProof voice tool is unavailable.',
      );
    }
    final fields = fpMap(fpMap(schema['parameters'])['properties']);
    if (args.length != fields.length ||
        args.keys.any((x) => !fields.containsKey(x))) {
      throw const FieldProofException('Use only the supported request fields.');
    }
    for (final entry in fields.entries) {
      final spec = fpMap(entry.value), v = args[entry.key];
      if (spec['type'] == 'boolean') {
        if (v is! bool) {
          throw const FieldProofException(
            'Choose whether this follow-up blocks closeout.',
          );
        }
      } else if (v is! String ||
          v.length > (spec['maxLength'] as int? ?? 4000) ||
          (spec['enum'] is List && !(spec['enum'] as List).contains(v))) {
        throw const FieldProofException('Use a valid field and value.');
      }
    }
    if (!['get_fieldproof_context', 'search_fieldproof_jobs'].contains(name) &&
        _context.isEmpty) {
      throw const FieldProofException('Read get_fieldproof_context first.');
    }
    if (name == 'read_fieldproof_job' && !_known.containsKey(args['job_id'])) {
      throw const FieldProofException(
        'Choose a real job returned by context or search.',
      );
    }
    if (name == 'start_fieldproof_draft' &&
        !_templates.containsKey(args['template'])) {
      throw const FieldProofException('Choose a template returned by context.');
    }
    if (name == 'update_fieldproof_field' &&
        (args['value'] as String).length > fpVoiceFields[args['field']]!) {
      throw const FieldProofException('Shorten the field value.');
    }
    return args;
  }

  Future<Map<String, dynamic>> handleToolCall(
    String name,
    dynamic raw,
    String callId,
  ) {
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
                  const FieldProofException(
                    'A repeated request changed. Ask again.',
                  ),
                ),
              );
      }
      if (callId.trim().isEmpty || callId.length > 200 || _count >= 64) {
        throw const FieldProofException(
          'Close voice and reopen it from FieldProof before another request.',
        );
      }
      if (_busy) {
        throw const FieldProofException(
          'Wait for the current FieldProof request to finish.',
        );
      }
      _count++;
      final epoch = _epoch;
      final future = _execute(name, args, epoch);
      _calls[callId] = (fingerprint: fingerprint, epoch: epoch, future: future);
      return future;
    } catch (e) {
      return Future.value(_error(e));
    }
  }

  Map<String, dynamic> _summary(Map<String, dynamic> job) {
    final d = fpMap(job['data']);
    return {
      'id': job['id'],
      'version': job['version'],
      'state': job['state'],
      for (final k in [
        'title',
        'customer',
        'site',
        'workOrder',
        'assetId',
        'priority',
        'stage',
        'dueOn',
      ])
        k: d[k],
      'needsAttention': fpNeedsAttention(job),
      'overdue': fpOverdue(job),
    };
  }

  Map<String, dynamic>? _jobContext() {
    if (_job.isEmpty) return null;
    return {
      'job': _job,
      'readiness': _selected['readiness'],
      'photos': fpRows(_selected['evidence'])
          .map(
            (x) => {
              for (final k in [
                'id',
                'name',
                'tag',
                'note',
                'state',
                'uploadedAt',
              ])
                k: x[k],
            },
          )
          .toList(),
      'photos_viewed': false,
    };
  }

  Future<Map<String, dynamic>> _execute(
    String name,
    Map<String, dynamic> args,
    int epoch,
  ) async {
    _busy = true;
    _result = {};
    _notify();
    try {
      if (name == 'get_fieldproof_context' ||
          name == 'search_fieldproof_jobs') {
        final response = await client.load();
        if (!_current(epoch)) return _discarded();
        if (response['jobs'] is! List || response['templates'] is! Map) {
          throw const FieldProofException(
            'Refresh FieldProof before another voice request.',
          );
        }
        _templates = fpMap(response['templates']);
        _known.clear();
        for (final job in fpRows(response['jobs'])) {
          if (job['id'] is! String ||
              job['data'] is! Map ||
              job['version'] is! int) {
            throw const FieldProofException(
              'The job list could not be verified.',
            );
          }
          _known[job['id'] as String] = job;
        }
        if (name == 'get_fieldproof_context' && _job.isNotEmpty) {
          final id = fpText(_job['id']), oldVersion = _job['version'];
          final current = await client.job(id);
          if (!_current(epoch)) return _discarded();
          if (_draft != null &&
              fpMap(current['job'])['version'] != oldVersion) {
            _draft = null;
            _pendingDraft = null;
            _selected = current;
            throw const FieldProofException(
              'This job changed. Read it again before drafting.',
            );
          }
          _selected = current;
        }
        final query = fpText(args['query']).trim().toLowerCase();
        final matches = _known.values
            .where(
              (j) =>
                  query.isEmpty ||
                  ['title', 'customer', 'site', 'workOrder', 'assetId'].any(
                    (k) => fpText(
                      fpMap(j['data'])[k],
                    ).toLowerCase().contains(query),
                  ),
            )
            .toList();
        _context = {
          'templates': _templates,
          'selected': _jobContext(),
          'working_draft': _draft,
          'jobs': matches.take(15).map(_summary).toList(),
          'has_more': matches.length > 15,
          'total': matches.length,
        };
        _result = {
          ..._context,
          'success': true,
          'kind': name == 'get_fieldproof_context' ? 'context' : 'search',
          'saved': false,
          'data_is_untrusted': true,
        };
      } else if (name == 'read_fieldproof_job') {
        final snapshot = await client.job(args['job_id']);
        if (!_current(epoch)) return _discarded();
        _selected = snapshot;
        _draft = null;
        _pendingDraft = null;
        _pendingOpen = {'action': 'open', 'jobId': _job['id']};
        _result = {
          'success': true,
          'kind': 'job',
          'selected': _jobContext(),
          'saved': false,
          'data_is_untrusted': true,
        };
      } else {
        Map<String, dynamic> draft;
        final starting = name == 'start_fieldproof_draft';
        if (starting) {
          draft = fpNewDraft(
            args['template'],
            fpMap(_templates[args['template']]),
          );
        } else {
          if (_draft == null && _job.isEmpty) {
            throw const FieldProofException(
              'Start a draft or read a saved job first.',
            );
          }
          draft = fpClone(_draft ?? fpMap(_job['data']));
        }
        _pendingDraft = null;
        if (name == 'update_fieldproof_field') {
          draft[args['field']] = args['value'];
        }
        if (name == 'add_fieldproof_reading') {
          draft['readings'] = [
            ...fpRows(draft['readings']),
            {'id': fieldProofRequestKey(), ...args},
          ];
        }
        if (name == 'add_fieldproof_issue') {
          draft['issues'] = [
            ...fpRows(draft['issues']),
            {'id': fieldProofRequestKey(), ...args, 'resolved': false},
          ];
        }
        final id = starting ? null : _job['id'] as String?,
            revision = starting ? null : _job['version'] as int?;
        final response = await client.prepareVoiceDraft(id, revision, draft);
        if (!_current(epoch)) return _discarded();
        if (response['saved'] != false ||
            response['reviewRequired'] != true ||
            response['draft'] is! Map ||
            response['jobId'] != id ||
            response['version'] != revision) {
          throw const FieldProofException(
            'The draft could not be verified. Review the job in FieldProof.',
          );
        }
        if (starting) {
          _selected = {};
          _pendingOpen = null;
        }
        _draft = fpClone(fpMap(response['draft']));
        _pendingDraft = {
          'action': 'draft',
          'jobId': id,
          'version': revision,
          'draft': _draft,
        };
        _result = {
          'success': true,
          'kind': 'draft',
          'draft': _draft,
          'saved': false,
          'reviewRequired': true,
          'readyToSave': response['readyToSave'],
          'data_is_untrusted': true,
          'message':
              'Unsaved draft ready. Tap Review in FieldProof, check the entries and save there.',
        };
      }
      if (!_current(epoch)) return _discarded();
      _notify();
      return result;
    } catch (e) {
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
    _known.clear();
    _draft = null;
    _pendingDraft = null;
    _pendingOpen = null;
    _result = {};
    _context = {};
    _selected = {};
    super.dispose();
  }
}
