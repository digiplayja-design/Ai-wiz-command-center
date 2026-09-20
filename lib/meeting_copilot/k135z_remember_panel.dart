import 'package:flutter/material.dart';
import 'k135z_remember_memory.dart';

class K135zRememberPanel extends StatefulWidget {
  const K135zRememberPanel({super.key, required this.memory});
  final K135zRememberMemory memory;
  @override
  State<K135zRememberPanel> createState() => _K135zRememberPanelState();
}

class _K135zRememberPanelState extends State<K135zRememberPanel> {
  final _password = TextEditingController();
  late final TextEditingController _text = TextEditingController(text:widget.memory.text);
  Future<void> _prepare() async {
    final password = _password.text;
    _password.clear();
    await widget.memory.prepare(password);
  }
  @override
  void dispose() { _password.clear(); _password.dispose(); _text.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation:widget.memory, builder:(context, _) {
    final m = widget.memory;
    return Card(child:Padding(padding:const EdgeInsets.all(16), child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,
      children:[
        Text('Remember in ${m.agentName}', style:Theme.of(context).textTheme.titleLarge),
        const SizedBox(height:8),
        if (m.active) ...[
          const Text('Only the fact you confirm is saved. Zoom captions can contain mistakes.'),
          const SizedBox(height:8),
          TextField(key:const Key('nova-memory-text'), controller:_text, enabled:!m.busy,
            minLines:2, maxLines:5, maxLength:2000, onChanged:m.edit,
            decoration:const InputDecoration(labelText:'What should Nova remember?')),
          if (m.phase == 'editing') ...[
            if (m.needsUnlock) TextField(key:const Key('nova-memory-password'),
              controller:_password, enabled:!m.busy, obscureText:true,
              autocorrect:false, enableSuggestions:false,
              decoration:const InputDecoration(labelText:'Brain Vault password — type only')),
            const SizedBox(height:8),
            FilledButton(key:const Key('nova-memory-preview'), onPressed:m.busy ? null : _prepare,
              child:Text(m.busy ? 'Preparing…' : m.needsUnlock ? 'Unlock & review' : 'Review memory')),
          ],
          if (m.phase == 'preview') ...[
            const Text('This is the exact memory that will be saved:'),
            SelectableText(m.preview!.normalizedText),
            const SizedBox(height:8),
            FilledButton(key:const Key('nova-memory-save'), onPressed:m.busy ? null : m.save,
              child:Text(m.busy ? 'Saving…' : 'Confirm save')),
          ],
        ],
        const SizedBox(height:8),
        Semantics(liveRegion:true, child:Text(m.message, key:const Key('nova-memory-status'))),
        TextButton(key:const Key('nova-memory-close'), onPressed:m.cancel,
          child:Text(m.active ? 'Cancel memory request' : 'Done')),
      ],
    )));
  });
}
