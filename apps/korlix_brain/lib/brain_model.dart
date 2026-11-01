/// The selected reasoning contract for this app build. Speech stays separate.
const brainModel = 'gpt-6.1-sol';
const brainProtocol = 'sol-6.1-max-v1';
const brainReasoningEffort = 'max';
const brainModelLabel = 'Sol 6.1 Max';

bool isBrainReasoningModel(Object? model) =>
    model is String &&
    (model == brainModel || model.startsWith('$brainModel-'));

bool hasBrainVoiceContract(Map<String, String> headers) =>
    headers['x-korlix-brain-voice'] == brainProtocol &&
    headers['x-korlix-brain-model'] == brainModel &&
    headers['x-korlix-brain-reasoning'] == brainReasoningEffort;
