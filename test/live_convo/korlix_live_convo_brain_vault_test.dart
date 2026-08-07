import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_brain_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KORLIX BRAIN VAULT foundation', () {
    const agent = KorlixLiveConvoAgent(
      id: 'doc_wizard',
      name: 'Doc Wizard',
      description: 'Professional document assistant.',
      iconName: 'description',
      accentHex: '62D6A7',
      mission: 'Create accurate professional documents.',
      trainingInstructions: 'Use concise five-point summaries.',
      toolIds: <String>[
        'general_chat',
        'live_docs',
        'file_analysis',
        'memory',
        'agent_training',
      ],
      memoryEnabled: true,
      memoryCount: 2,
      version: 4,
      persistenceConfigured: true,
    );

    final memories = <KorlixLiveConvoAgentMemory>[
      const KorlixLiveConvoAgentMemory(
        id: 'memory_public',
        agentId: 'doc_wizard',
        kind: 'preference',
        label: 'Report style',
        content: 'Use white-and-gold reports.',
        tags: <String>['reports'],
        importance: 4,
        sensitive: false,
        source: 'user_confirmed',
      ),
      const KorlixLiveConvoAgentMemory(
        id: 'memory_sensitive',
        agentId: 'doc_wizard',
        kind: 'fact',
        label: 'Private account note',
        content: 'This is private financial information.',
        tags: <String>['private'],
        importance: 5,
        sensitive: true,
        source: 'user_confirmed',
      ),
    ];

    final versions = <KorlixBrainVaultVersion>[
      KorlixBrainVaultVersion.fromJson(<String, dynamic>{
        'version': 4,
        'source': 'training_update',
        'snapshot': <String, dynamic>{
          'name': 'Doc Wizard',
          'trainingInstructions': 'Use concise five-point summaries.',
          'toolIds': <String>[
            'general_chat',
            'live_docs',
            'unknown_hidden_tool',
          ],
          'userId': 'must-not-export',
          'apiKey': 'must-not-export',
        },
      }),
    ];

    test('template excludes all memories and history', () {
      final package = KorlixBrainVaultPackage.fromAgent(
        agent: agent,
        memories: memories,
        versions: versions,
        includeMemories: false,
        includeSensitiveMemories: false,
        includeVersionHistory: false,
        mode: KorlixBrainVaultPackage.templateMode,
        exportedAt: DateTime.utc(2026, 8, 3),
      );

      expect(package.mode, KorlixBrainVaultPackage.templateMode);
      expect(package.memories, isEmpty);
      expect(package.versions, isEmpty);
      expect(package.agent.trainingInstructions, isNotEmpty);
    });

    test('private backup excludes sensitive memories by default', () {
      final package = KorlixBrainVaultPackage.fromAgent(
        agent: agent,
        memories: memories,
        versions: versions,
        includeMemories: true,
        includeSensitiveMemories: false,
        includeVersionHistory: true,
        mode: KorlixBrainVaultPackage.privateBackupMode,
      );

      expect(package.memories, hasLength(1));
      expect(package.memories.single.sensitive, isFalse);
      expect(package.versions, hasLength(1));
    });

    test('private backup includes sensitive memories only explicitly', () {
      final package = KorlixBrainVaultPackage.fromAgent(
        agent: agent,
        memories: memories,
        versions: versions,
        includeMemories: true,
        includeSensitiveMemories: true,
        includeVersionHistory: true,
        mode: KorlixBrainVaultPackage.privateBackupMode,
      );

      expect(package.memories, hasLength(2));
      expect(package.sensitiveMemoryCount, 1);

      final filtered = package.withSensitiveMemories(false);

      expect(filtered.memories, hasLength(1));
      expect(filtered.sensitiveMemoryCount, 0);
    });

    test('encoded package excludes account, billing, and secret fields', () {
      final package = KorlixBrainVaultPackage.fromAgent(
        agent: agent,
        memories: memories,
        versions: versions,
        includeMemories: true,
        includeSensitiveMemories: true,
        includeVersionHistory: true,
        mode: KorlixBrainVaultPackage.privateBackupMode,
      );

      final encoded = package.encodePretty();

      expect(encoded, isNot(contains('must-not-export')));
      expect(encoded, isNot(contains('"userId"')));
      expect(encoded, isNot(contains('"apiKey"')));
      expect(encoded, isNot(contains('"aiGasBalance"')));
      expect(encoded, isNot(contains('"authToken"')));
      expect(encoded, contains('AI GAS balances'));
    });

    test('decode filters unauthorized tools and ignores unknown fields', () {
      final source = '''
{
  "schema": "korlix.brain.v1",
  "mode": "private_backup",
  "exportedAt": "2026-08-03T12:00:00Z",
  "userId": "forged-owner",
  "authToken": "forged-token",
  "aiGasBalance": 999999,
  "agent": {
    "name": "Imported Helper",
    "mission": "Help with planning.",
    "trainingInstructions": "Use clear steps.",
    "toolIds": [
      "general_chat",
      "memory",
      "shell_access",
      "service_role"
    ],
    "memoryEnabled": true
  },
  "memories": [
    {
      "kind": "fact",
      "label": "Project",
      "content": "The project name is Northstar.",
      "importance": 3,
      "sensitive": false
    }
  ],
  "versions": []
}
''';

      final package = KorlixBrainVaultPackage.decode(source);

      expect(package.agent.name, 'Imported Helper');
      expect(package.agent.toolIds, contains('general_chat'));
      expect(package.agent.toolIds, contains('memory'));
      expect(package.agent.toolIds, isNot(contains('shell_access')));
      expect(package.agent.toolIds, isNot(contains('service_role')));
      expect(package.memories, hasLength(1));
    });

    test('import creates confirmed memory drafts with safe provenance', () {
      final package = KorlixBrainVaultPackage.fromAgent(
        agent: agent,
        memories: memories,
        versions: versions,
        includeMemories: true,
        includeSensitiveMemories: true,
        includeVersionHistory: false,
        mode: KorlixBrainVaultPackage.privateBackupMode,
      );

      final drafts = package.memoryDrafts(includeSensitiveMemories: false);

      expect(drafts, hasLength(1));
      expect(drafts.single.confirmed, isTrue);
      expect(drafts.single.source, 'brain_vault_import');
      expect(drafts.single.sensitive, isFalse);
    });

    test('imported agent draft never preserves a source agent ID', () {
      final package = KorlixBrainVaultPackage.fromAgent(
        agent: agent,
        memories: memories,
        versions: versions,
        includeMemories: false,
        includeSensitiveMemories: false,
        includeVersionHistory: false,
        mode: KorlixBrainVaultPackage.templateMode,
      );

      final draft = package.agent.toCustomAgentDraft(
        nameOverride: 'Copied Doc Wizard',
      );
      final json = draft.toJson();

      expect(json['name'], 'Copied Doc Wizard');
      expect(json, isNot(containsPair('id', 'doc_wizard')));
      expect(json, isNot(containsPair('userId', anything)));
      expect(json['trainingInstructions'], isNotEmpty);
    });

    test('rejects unsupported or malformed brain packages', () {
      expect(
        () => KorlixBrainVaultPackage.decode(
          '{"schema":"not-korlix","agent":{}}',
        ),
        throwsFormatException,
      );

      expect(() => KorlixBrainVaultPackage.decode('[]'), throwsFormatException);
    });
  });
}
