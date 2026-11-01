/// The selected reasoning contract for this app build. Speech stays separate.
const brainModel = 'gpt-6.1-sol';
const brainProtocol = 'sol-6.1-max-v1';
const brainReasoningEffort = 'max';
const brainModelLabel = 'Sol 6.1 Max';

enum BrainVoiceMode { live, deep }

extension BrainVoiceModeConfig on BrainVoiceMode {
  bool get isLive => this == BrainVoiceMode.live;
  String get protocol => isLive ? 'rici-live-v1' : brainProtocol;
  String get model => isLive ? 'gpt-realtime-2.1' : brainModel;
  String get effort => isLive ? 'low' : brainReasoningEffort;
  String get label => isLive ? 'Live conversation' : 'Deep Think · Sol Max';
  bool accepts(Map<String, String> headers) =>
      headers['x-korlix-brain-voice'] == protocol &&
      headers['x-korlix-brain-model'] == model &&
      headers['x-korlix-brain-reasoning'] == effort;
}

bool isBrainReasoningModel(Object? model) =>
    model is String &&
    (model == brainModel || model.startsWith('$brainModel-'));

bool hasBrainVoiceContract(Map<String, String> headers) =>
    headers['x-korlix-brain-voice'] == brainProtocol &&
    headers['x-korlix-brain-model'] == brainModel &&
    headers['x-korlix-brain-reasoning'] == brainReasoningEffort;
