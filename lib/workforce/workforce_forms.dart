import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'workforce_client.dart';
import 'workforce_style.dart';

class WfField {
  const WfField(
    this.keyName,
    this.label, {
    this.value = '',
    this.type = 'text',
    this.choices,
    this.required = true,
    this.lines = 1,
  });
  final String keyName, label, type;
  final dynamic value;
  final Map<String, String>? choices;
  final bool required;
  final int lines;
}

class WorkforceForm extends StatefulWidget {
  const WorkforceForm({
    super.key,
    required this.title,
    required this.description,
    required this.fields,
    required this.submit,
    this.button = 'Save',
    this.dictation = false,
  });
  final String title, description, button;
  final List<WfField> fields;
  final Future<void> Function(WfJson) submit;
  final bool dictation;
  @override
  State<WorkforceForm> createState() => _WorkforceFormState();
}

class _WorkforceFormState extends State<WorkforceForm> {
  final _key = GlobalKey<FormState>();
  final _values = <String, dynamic>{};
  final _controllers = <String, TextEditingController>{};
  final _speech = SpeechToText();
  bool _saving = false, _listening = false;
  String? _error;
  String _beforeSpeech = '';
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _values[f.keyName] = f.value;
      if (f.type != 'bool' && f.choices == null) {
        _controllers[f.keyName] = TextEditingController(
          text: f.value?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _dictate() async {
    try {
      if (_listening) {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
        return;
      }
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (mounted && s != 'listening') setState(() => _listening = false);
        },
        onError: (_) {
          if (mounted) {
            setState(() {
              _listening = false;
              _error = 'Speech input is unavailable. You can type your update.';
            });
          }
        },
      );
      if (!mounted) return;
      if (!ok) {
        setState(
          () => _error =
              'Allow microphone and speech access, or type your update.',
        );
        return;
      }
      _beforeSpeech = _controllers['summary']?.text ?? '';
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (r) {
          if (mounted) {
            _controllers['summary']?.text =
                '${_beforeSpeech.isEmpty ? '' : '$_beforeSpeech '}${r.recognizedWords}';
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Speech input is unavailable. You can type your update.',
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
      _listening = false;
    });
    try {
      for (final f in widget.fields) {
        if (_controllers.containsKey(f.keyName)) {
          final v = _controllers[f.keyName]!.text.trim();
          _values[f.keyName] = switch (f.type) {
            'int' => int.parse(v),
            'number' => v.isEmpty ? null : double.parse(v),
            'datetime' => DateTime.parse(v).toUtc().toIso8601String(),
            _ => v,
          };
        }
      }
      await widget.submit(Map.of(_values));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _pickDate(WfField f) async {
    final initial =
        DateTime.tryParse(_controllers[f.keyName]!.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    _controllers[f.keyName]!.text = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toIso8601String().substring(0, 16);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                style: const TextStyle(color: WfStyle.muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: f.type == 'bool'
                      ? SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.label),
                          value: _values[f.keyName] == true,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _values[f.keyName] = v),
                        )
                      : f.choices != null
                      ? DropdownButtonFormField<String>(
                          initialValue: _values[f.keyName]?.toString(),
                          isExpanded: true,
                          decoration: InputDecoration(labelText: f.label),
                          items: f.choices!.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (v) => _values[f.keyName] = v,
                        )
                      : TextFormField(
                          controller: _controllers[f.keyName],
                          enabled: !_saving,
                          maxLines: f.lines,
                          maxLength: f.keyName == 'summary'
                              ? 2000
                              : f.lines > 1
                              ? 1000
                              : null,
                          keyboardType: ['int', 'number'].contains(f.type)
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                )
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: f.label,
                            suffixIcon: f.type == 'datetime'
                                ? IconButton(
                                    onPressed: () => _pickDate(f),
                                    icon: const Icon(Icons.calendar_month),
                                    tooltip: 'Choose date and time',
                                  )
                                : null,
                          ),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (f.required && s.isEmpty) {
                              return 'This field is required.';
                            }
                            if (f.type == 'int' && int.tryParse(s) == null) {
                              return 'Enter a whole number.';
                            }
                            if (f.type == 'number' &&
                                s.isNotEmpty &&
                                double.tryParse(s) == null) {
                              return 'Enter a number.';
                            }
                            if (f.type == 'datetime' &&
                                DateTime.tryParse(s) == null) {
                              return 'Choose a date and time.';
                            }
                            return null;
                          },
                        ),
                ),
              if (widget.dictation) ...[
                OutlinedButton.icon(
                  onPressed: _saving ? null : _dictate,
                  icon: Icon(_listening ? Icons.stop : Icons.mic_none),
                  label: Text(
                    _listening ? 'Stop dictation' : 'Dictate work update',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Review the text before saving. Speech input uses your device’s speech service.',
                    style: TextStyle(color: WfStyle.muted, fontSize: 12),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: WfStyle.danger),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : widget.button),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class WorkforcePunchDialog extends StatefulWidget {
  const WorkforcePunchDialog({
    super.key,
    required this.clockOut,
    required this.policy,
    required this.submit,
  });
  final bool clockOut;
  final WfJson policy;
  final Future<void> Function(WfJson) submit;
  @override
  State<WorkforcePunchDialog> createState() => _WorkforcePunchDialogState();
}

class _WorkforcePunchDialogState extends State<WorkforcePunchDialog> {
  Uint8List? _photo;
  WfJson? _location;
  bool _busy = false, _saving = false, _confirmed = false;
  String? _error;
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
      );
      final bytes = await image?.readAsBytes();
      if (mounted) {
        setState(() {
          _photo = bytes;
          _confirmed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Camera is unavailable. You can record an exception below.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _locate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception();
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) {
        setState(
          () => _location = {
            'latitude': p.latitude,
            'longitude': p.longitude,
            'accuracy': p.accuracy,
            'captured_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Location is unavailable. Enable location access or record an exception.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final missing =
        (widget.policy['require_selfie'] == true && _photo == null) ||
        (widget.policy['require_location'] == true && _location == null);
    if (_photo != null && !_confirmed) {
      setState(() => _error = 'Please confirm the photo is ready to submit.');
      return;
    }
    if (!widget.clockOut && missing && _reason.text.trim().length < 5) {
      setState(
        () => _error =
            'Capture the required evidence or explain why it is unavailable.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.submit({
        'selfie': _photo == null ? null : base64Encode(_photo!),
        'capture_confirmed': _confirmed,
        'location': _location,
        'exception_reason': _reason.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.clockOut
                        ? 'Finish your shift'
                        : 'Start your workday',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Your attendance time is recorded when the server receives your confirmation. Photos and location are captured only when you request them.',
              style: const TextStyle(color: WfStyle.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            WfBadge('${widget.policy['worksite'] ?? 'Worksite'}'),
            const SizedBox(height: 16),
            if (widget.policy['require_selfie'] == true) ...[
              OutlinedButton.icon(
                onPressed: _busy || _saving ? null : _capture,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(
                  _photo == null ? 'Capture attendance photo' : 'Retake photo',
                ),
              ),
              if (_photo != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    _photo!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmed,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _confirmed = v ?? false),
                  title: const Text('I reviewed this photo.'),
                ),
              ],
              const Text(
                'Photo evidence for your employer. No facial identification or matching.',
                style: TextStyle(color: WfStyle.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
            ],
            if (widget.policy['require_location'] == true) ...[
              OutlinedButton.icon(
                onPressed: _busy || _saving ? null : _locate,
                icon: const Icon(Icons.my_location),
                label: Text(
                  _location == null
                      ? 'Capture current location'
                      : 'Refresh location',
                ),
              ),
              if (_location != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${(_location!['latitude'] as num).toStringAsFixed(5)}, ${(_location!['longitude'] as num).toStringAsFixed(5)} · accuracy ±${(_location!['accuracy'] as num).round()} m',
                    style: const TextStyle(color: WfStyle.cyan),
                  ),
                ),
              const Text(
                'A location stamp for this attendance event. No background tracking.',
                style: TextStyle(color: WfStyle.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _reason,
              enabled: !_saving,
              maxLines: 2,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Exception or note (if needed)',
                hintText: 'Camera unavailable, working off-site…',
              ),
            ),
            Text(
              'Evidence expires after ${widget.policy['retention_days'] ?? 30} days. ${widget.clockOut ? 'Missing evidence flags this shift for review; it does not prevent clock-out.' : 'Exceptions go to your manager for review.'}',
              style: const TextStyle(
                color: WfStyle.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: WfStyle.danger),
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || _saving ? null : _save,
                icon: Icon(widget.clockOut ? Icons.logout : Icons.login),
                label: Text(
                  _saving
                      ? 'Recording…'
                      : widget.clockOut
                      ? 'Confirm clock-out'
                      : 'Confirm clock-in',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
