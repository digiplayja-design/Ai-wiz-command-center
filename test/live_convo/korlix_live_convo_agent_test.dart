import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Korlix LIVE CONVO Agent Hub model', () {
    test('provides the five built-in trainable fallback agents', () {
      final agents =
          KorlixLiveConvoAgent.builtInFallbacks;

      expect(
        agents.map((agent) => agent.id),
        <String>[
          'general',
          'doc_wizard',
          'language_teacher',
          'my_assistant',
          'graphic_designer',
        ],
      );

      for (final agent in agents) {
        expect(agent.memoryEnabled, isTrue);
        expect(
          agent.toolIds,
          contains('general_chat'),
        );
        expect(
          agent.toolIds,
          contains('memory'),
        );
        expect(
          agent.toolIds,
          contains('agent_training'),
        );
      }
    });

    test('parses a trained backend agent profile', () {
      final agent = KorlixLiveConvoAgent.fromJson(
        <String, dynamic>{
          'id': 'doc_wizard',
          'name': 'Doc Wizard',
          'description': 'Professional reports.',
          'icon': 'description',
          'accent': '#62D6A7',
          'mission': 'Create accurate documents.',
          'trainingInstructions':
              'Always add an executive summary.',
          'toolIds': <String>[
            'general_chat',
            'live_docs',
            'memory',
            'agent_training',
          ],
          'memoryEnabled': true,
          'memoryCount': 7,
          'isCustom': false,
          'active': true,
          'version': 4,
          'persistenceConfigured': true,
        },
      );

      expect(agent.id, 'doc_wizard');
      expect(agent.name, 'Doc Wizard');
      expect(agent.accentHex, '62D6A7');
      expect(agent.memoryCount, 7);
      expect(agent.version, 4);
      expect(agent.canUseLiveDocs, isTrue);
      expect(agent.canUseMemory, isTrue);
      expect(agent.hasPublishedTraining, isTrue);
      expect(agent.memoryPersistenceReady, isTrue);
      expect(agent.memorySummary, '7 memories');
    });

    test('parses runtime model and deterministic-engine proof', () {
      final runtime = KorlixLiveConvoAgentRuntime.fromJson(
        <String, dynamic>{
          'agent': <String, dynamic>{
            'id': 'doc_wizard',
            'name': 'Doc Wizard',
            'memoryEnabled': true,
            'toolIds': <String>[
              'general_chat',
              'live_docs',
              'memory',
              'agent_training',
            ],
          },
          'toolIds': <String>[
            'general_chat',
            'live_docs',
            'memory',
            'agent_training',
          ],
          'memoryCount': 2,
          'appliedMemories': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'memory-1',
              'kind': 'preference',
              'label': 'Report style',
              'importance': 5,
              'sensitive': false,
            },
          ],
          'modelProof': <String, dynamic>{
            'liveConvoModel': 'gpt-realtime-2.1',
            'liveDocsDocumentModel': 'gpt-5.6',
            'liveDocsReasoningEffort': 'high',
            'deterministicAuditEngine': true,
          },
          'persistenceConfigured': true,
          'runtimeVersion':
              'korlix.live_convo.agent.build131.v1',
        },
      );

      expect(runtime.agent.id, 'doc_wizard');
      expect(runtime.memoryCount, 2);
      expect(runtime.appliedMemories, hasLength(1));
      expect(
        runtime.modelProof.liveConvoModel,
        'gpt-realtime-2.1',
      );
      expect(
        runtime.modelProof.liveDocsDocumentModel,
        'gpt-5.6',
      );
      expect(
        runtime.modelProof.provesGpt56DocumentReasoning,
        isTrue,
      );
      expect(
        runtime.modelProof.deterministicAuditEngine,
        isTrue,
      );
      expect(runtime.persistenceConfigured, isTrue);
    });

    test('builds explicit confirmed training payloads', () {
      const update = KorlixLiveConvoAgentTrainingUpdate(
        instructions:
            'Use concise internal operations reports.',
        confirmed: true,
        toolIds: <String>[
          'general_chat',
          'live_docs',
          'memory',
          'agent_training',
        ],
        memoryEnabled: true,
        source: 'voice_training',
      );

      final json = update.toJson();

      expect(json['confirmed'], isTrue);
      expect(
        json['trainingInstructions'],
        'Use concise internal operations reports.',
      );
      expect(json['memoryEnabled'], isTrue);
      expect(json['source'], 'voice_training');
    });

    test('builds bounded explicit memory payloads', () {
      const draft = KorlixLiveConvoMemoryDraft(
        content:
            'Use one-page executive summaries.',
        confirmed: true,
        kind: 'preference',
        label: 'Report style',
        tags: <String>[
          'reports',
          'executive',
        ],
        importance: 9,
        sensitive: false,
      );

      final json = draft.toJson();

      expect(json['confirmed'], isTrue);
      expect(json['kind'], 'preference');
      expect(json['importance'], 5);
      expect(json['sensitive'], isFalse);
    });

    test('builds encoded Agent Hub API paths', () {
      expect(
        KorlixLiveConvoAgentApiContract.runtimePath(
          'custom brand coach',
        ),
        '/api/live-convo/agents/'
        'custom%20brand%20coach/runtime',
      );

      expect(
        KorlixLiveConvoAgentApiContract.memoryPath(
          'doc_wizard',
          'memory/one',
        ),
        '/api/live-convo/agents/doc_wizard/'
        'memories/memory%2Fone',
      );

      expect(
        KorlixLiveConvoAgentApiContract
            .restoreVersionPath(
          'my_assistant',
          4,
        ),
        '/api/live-convo/agents/'
        'my_assistant/versions/4/restore',
      );
    });
  });
}
