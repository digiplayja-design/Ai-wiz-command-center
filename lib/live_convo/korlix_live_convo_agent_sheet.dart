import 'dart:async';

import 'package:flutter/material.dart';

import 'korlix_live_convo_agent.dart';
import 'korlix_live_convo_agent_client.dart';

// KORLIX_LIVE_CONVO_AGENT_SHEET_BUILD131_BEGIN

Future<KorlixLiveConvoAgentRuntime?>
showKorlixLiveConvoAgentHub({
  required BuildContext context,
  required KorlixLiveConvoAgentClient client,
  required KorlixLiveConvoAgent activeAgent,
  required String characterName,
  required String language,
}) {
  return showModalBottomSheet<KorlixLiveConvoAgentRuntime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xCC02070C),
    builder: (sheetContext) {
      return KorlixLiveConvoAgentHubSheet(
        client: client,
        activeAgent: activeAgent,
        characterName: characterName,
        language: language,
      );
    },
  );
}

IconData korlixLiveConvoAgentIcon(String value) {
  switch (value.trim().toLowerCase()) {
    case 'description':
    case 'article':
      return Icons.description_rounded;

    case 'translate':
    case 'language':
      return Icons.translate_rounded;

    case 'support_agent':
    case 'assistant':
      return Icons.support_agent_rounded;

    case 'palette':
    case 'design':
      return Icons.palette_rounded;

    case 'smart_toy':
    case 'robot':
      return Icons.smart_toy_rounded;

    case 'school':
      return Icons.school_rounded;

    case 'work':
      return Icons.work_rounded;

    case 'campaign':
      return Icons.campaign_rounded;

    case 'psychology':
      return Icons.psychology_rounded;

    case 'auto_awesome':
    default:
      return Icons.auto_awesome_rounded;
  }
}

Color korlixLiveConvoAgentAccent(String value) {
  final clean = value
      .trim()
      .replaceFirst('#', '')
      .toUpperCase();

  if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) {
    return const Color(0xFF21D4F4);
  }

  return Color(
    int.parse(
      'FF$clean',
      radix: 16,
    ),
  );
}

class KorlixLiveConvoAgentHubSheet
    extends StatefulWidget {
  const KorlixLiveConvoAgentHubSheet({
    super.key,
    required this.client,
    required this.activeAgent,
    required this.characterName,
    required this.language,
  });

  final KorlixLiveConvoAgentClient client;
  final KorlixLiveConvoAgent activeAgent;
  final String characterName;
  final String language;

  @override
  State<KorlixLiveConvoAgentHubSheet>
  createState() {
    return _KorlixLiveConvoAgentHubSheetState();
  }
}

class _KorlixLiveConvoAgentHubSheetState
    extends State<KorlixLiveConvoAgentHubSheet> {
  KorlixLiveConvoAgentCatalog _catalog =
      KorlixLiveConvoAgentCatalog.fallback;

  KorlixLiveConvoAgentModelProof _modelProof =
      const KorlixLiveConvoAgentModelProof();

  late String _selectedAgentId;

  bool _loading = true;
  bool _busy = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    final activeId =
        widget.activeAgent.id.trim();

    _selectedAgentId =
        activeId.isEmpty
            ? 'general'
            : activeId;

    unawaited(_load());
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst(
          'KorlixLiveConvoAgentClientException: ',
          '',
        )
        .replaceFirst(
          'Exception: ',
          '',
        )
        .trim();
  }

  KorlixLiveConvoAgent get _selectedAgent {
    return _catalog.agentById(
          _selectedAgentId,
        ) ??
        widget.activeAgent;
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    var catalog =
        KorlixLiveConvoAgentCatalog.fallback;

    var modelProof =
        const KorlixLiveConvoAgentModelProof();

    Object? catalogError;
    Object? proofError;

    try {
      catalog =
          await widget.client.loadCatalog();
    } catch (error) {
      catalogError = error;
    }

    try {
      modelProof =
          await widget.client.loadModelProof();
    } catch (error) {
      proofError = error;
    }

    if (!mounted) {
      return;
    }

    final selectedExists =
        catalog.agentById(
          _selectedAgentId,
        ) !=
        null;

    setState(() {
      _catalog = catalog;
      _modelProof = modelProof;
      _loading = false;

      if (!selectedExists) {
        _selectedAgentId = 'general';
      }

      if (catalogError != null) {
        _error = _cleanError(catalogError);
      } else if (proofError != null) {
        _error =
            'Agents loaded, but model proof '
            'is unavailable: '
            '${_cleanError(proofError)}';
      }
    });
  }
  void _replaceAgent(
    KorlixLiveConvoAgent updated,
  ) {
    final agents =
        <KorlixLiveConvoAgent>[];

    var replaced = false;

    for (final agent in _catalog.agents) {
      if (agent.id == updated.id) {
        agents.add(updated);
        replaced = true;
      } else {
        agents.add(agent);
      }
    }

    if (!replaced) {
      agents.add(updated);
    }

    setState(() {
      _catalog =
          KorlixLiveConvoAgentCatalog(
        agents:
            List<KorlixLiveConvoAgent>.unmodifiable(
          agents,
        ),
        persistenceConfigured:
            _catalog.persistenceConfigured ||
            updated.persistenceConfigured,
      );

      _selectedAgentId = updated.id;
    });
  }

  Future<T?> _runBusy<T>(
    Future<T> Function() callback,
  ) async {
    if (_busy) {
      return null;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      return await callback();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _cleanError(error);
        });
      }

      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error
              ? const Color(0xFF8D3344)
              : const Color(0xFF17644D),
          duration:
              const Duration(seconds: 5),
        ),
      );
  }

  Future<void> _activateAgent(
    KorlixLiveConvoAgent agent,
  ) async {
    final runtime =
        await _runBusy<
            KorlixLiveConvoAgentRuntime>(
      () {
        return widget.client.loadRuntime(
          agentId: agent.id,
          characterName:
              widget.characterName,
          language:
              widget.language,
        );
      },
    );

    if (!mounted || runtime == null) {
      return;
    }

    Navigator.of(context).pop(runtime);
  }

  Widget _buildHeader() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        18,
        12,
        12,
        10,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(16),
              color:
                  const Color(0xFF123A47),
              border: Border.all(
                color:
                    const Color(0xFF21D4F4),
              ),
            ),
            child: const Icon(
              Icons.hub_rounded,
              color:
                  Color(0xFF69D9E8),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE CONVO AGENTS',
                  style: TextStyle(
                    color:
                        Color(0xFFF0F7F8),
                    fontSize: 20,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Select, train, and manage '
                  'private long-term memory.',
                  style: TextStyle(
                    color:
                        Color(0xFFA9C6CF),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close Agent Hub',
            onPressed: _busy
                ? null
                : () {
                    Navigator.of(context).pop();
                  },
            icon: const Icon(
              Icons.close_rounded,
            ),
            color:
                const Color(0xFFC7D7DC),
          ),
        ],
      ),
    );
  }

  Widget _buildModelProofCard() {
    final provesGpt56 =
        _modelProof
            .provesGpt56DocumentReasoning;

    final liveConvoModel =
        _modelProof.liveConvoModel
                .trim()
                .isEmpty
            ? 'Unavailable'
            : _modelProof.liveConvoModel;

    final documentModel =
        _modelProof
                .liveDocsDocumentModel
                .trim()
                .isEmpty
            ? 'Unavailable'
            : _modelProof
                .liveDocsDocumentModel;

    final reasoningEffort =
        _modelProof
            .liveDocsReasoningEffort
            .trim();

    final documentLine =
        reasoningEffort.isEmpty
            ? 'LIVE DOCS reasoning: '
                '$documentModel'
            : 'LIVE DOCS reasoning: '
                '$documentModel · '
                '$reasoningEffort';

    final proofColor = provesGpt56
        ? const Color(0xFF62D6A7)
        : const Color(0xFFF2C14E);

    return Container(
      margin:
          const EdgeInsets.fromLTRB(
        16,
        4,
        16,
        12,
      ),
      padding:
          const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(18),
        color:
            const Color(0xFF081B25),
        border: Border.all(
          color: proofColor.withValues(
            alpha: 0.64,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                provesGpt56
                    ? Icons.verified_rounded
                    : Icons
                        .info_outline_rounded,
                color: proofColor,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  provesGpt56
                      ? 'Runtime model '
                          'proof verified'
                      : 'Runtime model proof',
                  style: TextStyle(
                    color: proofColor,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'LIVE CONVO voice: '
            '$liveConvoModel',
            style: const TextStyle(
              color:
                  Color(0xFFD8E7EA),
              fontWeight:
                  FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            documentLine,
            style: const TextStyle(
              color:
                  Color(0xFFD8E7EA),
              fontWeight:
                  FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _modelProof
                    .deterministicAuditEngine
                ? 'Technician-audit '
                    'calculations: '
                    'deterministic engine'
                : 'Deterministic audit '
                    'proof unavailable',
            style: const TextStyle(
              color:
                  Color(0xFFA9C6CF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersistenceNotice() {
    final configured =
        _catalog.persistenceConfigured;

    final color = configured
        ? const Color(0xFF62D6A7)
        : const Color(0xFFF2C14E);

    return Container(
      margin:
          const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color: configured
            ? const Color(0xFF0B2A24)
            : const Color(0xFF332916),
        border: Border.all(
          color: color,
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            configured
                ? Icons.cloud_done_rounded
                : Icons.storage_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              configured
                  ? 'Private agent training '
                      'and long-term memory '
                      'are connected.'
                  : 'Agent selection is '
                      'available. Apply the '
                      'included Supabase '
                      'migration before '
                      'saving training or '
                      'long-term memory.',
              style: const TextStyle(
                color:
                    Color(0xFFD8E7EA),
                height: 1.35,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildErrorBanner() {
    final error = _error?.trim() ?? '';

    if (error.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF351923),
        border: Border.all(
          color: const Color(0xFFFF7185),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF8B9B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: Color(0xFFFFD8DE),
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Retry',
            onPressed: _busy
                ? null
                : () {
                    unawaited(_load());
                  },
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            color: const Color(0xFFFFB2BE),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentCard(
    KorlixLiveConvoAgent agent,
  ) {
    final accent =
        korlixLiveConvoAgentAccent(
      agent.accentHex,
    );

    final selected =
        agent.id == _selectedAgentId;

    final currentlyActive =
        agent.id == widget.activeAgent.id;

    final enabled =
        agent.active && !_busy;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              BorderRadius.circular(20),
          onTap: enabled
              ? () {
                  setState(() {
                    _selectedAgentId =
                        agent.id;
                  });
                }
              : null,
          child: AnimatedContainer(
            duration:
                const Duration(milliseconds: 180),
            padding:
                const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(20),
              color: selected
                  ? accent.withValues(
                      alpha: 0.13,
                    )
                  : const Color(0xFF071722),
              border: Border.all(
                color: selected
                    ? accent
                    : const Color(0xFF244D5C),
                width:
                    selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(
                          alpha: 0.12,
                        ),
                        blurRadius: 22,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(
                          15,
                        ),
                        color: accent.withValues(
                          alpha: 0.16,
                        ),
                        border: Border.all(
                          color: accent.withValues(
                            alpha: 0.72,
                          ),
                        ),
                      ),
                      child: Icon(
                        korlixLiveConvoAgentIcon(
                          agent.iconName,
                        ),
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 7,
                            runSpacing: 6,
                            crossAxisAlignment:
                                WrapCrossAlignment
                                    .center,
                            children: [
                              Text(
                                agent.name,
                                style:
                                    const TextStyle(
                                  color:
                                      Color(0xFFF0F7F8),
                                  fontSize: 17,
                                  fontWeight:
                                      FontWeight.w900,
                                ),
                              ),
                              if (currentlyActive)
                                _KorlixAgentBadge(
                                  text: 'ACTIVE',
                                  color: accent,
                                ),
                              if (agent.isCustom)
                                const _KorlixAgentBadge(
                                  text: 'CUSTOM',
                                  color:
                                      Color(0xFFB794F4),
                                ),
                              if (agent
                                  .hasPublishedTraining)
                                const _KorlixAgentBadge(
                                  text: 'TRAINED',
                                  color:
                                      Color(0xFF62D6A7),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            agent.description,
                            style: const TextStyle(
                              color:
                                  Color(0xFFA9C6CF),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: const Duration(
                        milliseconds: 160,
                      ),
                      child: selected
                          ? Icon(
                              Icons
                                  .check_circle_rounded,
                              key: ValueKey<String>(
                                'selected-${agent.id}',
                              ),
                              color: accent,
                              size: 26,
                            )
                          : Icon(
                              Icons
                                  .radio_button_unchecked_rounded,
                              key: ValueKey<String>(
                                'idle-${agent.id}',
                              ),
                              color: const Color(
                                0xFF66818A,
                              ),
                              size: 26,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      agent.memoryEnabled
                          ? Icons
                              .psychology_alt_rounded
                          : Icons
                              .memory_outlined,
                      size: 19,
                      color: agent.memoryEnabled
                          ? const Color(
                              0xFF8CDDE8,
                            )
                          : const Color(
                              0xFF9AA8AD,
                            ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        agent.memorySummary,
                        style: TextStyle(
                          color:
                              agent.memoryEnabled
                              ? const Color(
                                  0xFF8CDDE8,
                                )
                              : const Color(
                                  0xFF9AA8AD,
                                ),
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Version ${agent.version}',
                      style: const TextStyle(
                        color:
                            Color(0xFF8299A2),
                        fontSize: 12,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: enabled
                          ? () {
                              unawaited(
                                _activateAgent(
                                  agent,
                                ),
                              );
                            }
                          : null,
                      style:
                          FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor:
                            const Color(
                          0xFF03110E,
                        ),
                      ),
                      icon: const Icon(
                        Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        currentlyActive
                            ? 'Reload Agent'
                            : 'Use Agent',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: enabled
                          ? () {
                              unawaited(
                                _openTraining(
                                  agent,
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(
                        Icons.school_rounded,
                      ),
                      label:
                          const Text('Train'),
                    ),
                    OutlinedButton.icon(
                      onPressed: enabled
                          ? () {
                              unawaited(
                                _openMemoryManager(
                                  agent,
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(
                        Icons
                            .psychology_alt_rounded,
                      ),
                      label:
                          const Text('Memory'),
                    ),
                    PopupMenuButton<String>(
                      enabled: enabled,
                      tooltip:
                          'More agent options',
                      color:
                          const Color(0xFF071722),
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color:
                            Color(0xFFC7D7DC),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'versions':
                            unawaited(
                              _openVersionHistory(
                                agent,
                              ),
                            );
                            break;

                          case 'reset':
                            unawaited(
                              _resetOrDeleteAgent(
                                agent,
                              ),
                            );
                            break;
                        }
                      },
                      itemBuilder: (context) {
                        return <
                            PopupMenuEntry<String>>[
                          const PopupMenuItem<
                              String>(
                            value: 'versions',
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.history_rounded,
                              ),
                              title: Text(
                                'Training history',
                              ),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'reset',
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                agent.isCustom
                                    ? Icons
                                        .delete_outline_rounded
                                    : Icons
                                        .restart_alt_rounded,
                              ),
                              title: Text(
                                agent.isCustom
                                    ? 'Delete custom agent'
                                    : 'Reset personal training',
                              ),
                            ),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAgentCatalog() {
    final agents = _catalog.agents
        .where(
          (agent) => agent.active,
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Padding(
            padding:
                EdgeInsets.fromLTRB(
              16,
              6,
              16,
              14,
            ),
            child: LinearProgressIndicator(
              minHeight: 3,
              color:
                  Color(0xFF69D9E8),
              backgroundColor:
                  Color(0xFF123A47),
            ),
          ),
        for (final agent in agents)
          _buildAgentCard(agent),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(
            16,
            2,
            16,
            10,
          ),
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () {
                    unawaited(
                      _openCustomAgentCreator(),
                    );
                  },
            style:
                OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 16,
              ),
              side: const BorderSide(
                color:
                    Color(0xFFB794F4),
              ),
              foregroundColor:
                  const Color(0xFFE0CBFF),
            ),
            icon: const Icon(
              Icons.add_circle_outline_rounded,
            ),
            label: const Text(
              'Create Your Own Agent',
              style: TextStyle(
                fontWeight:
                    FontWeight.w900,
              ),
            ),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16,
          ),
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () {
                    unawaited(_load());
                  },
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text(
              'Refresh Agent Hub',
            ),
          ),
        ),
      ],
    );
  }
  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !_busy,
      builder: (dialogContext) {
        final confirmColor = destructive
            ? const Color(0xFFFF7185)
            : const Color(0xFF62D6A7);

        return AlertDialog(
          backgroundColor:
              const Color(0xFF071722),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF0F7F8),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Color(0xFFBBD0D6),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor:
                    const Color(0xFF03110E),
              ),
              child: Text(
                confirmLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _openTraining(
    KorlixLiveConvoAgent agent,
  ) async {
    final update = await showModalBottomSheet<
        KorlixLiveConvoAgentTrainingUpdate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xCC02070C),
      builder: (sheetContext) {
        return _KorlixAgentTrainingSheet(
          agent: agent,
        );
      },
    );

    if (!mounted || update == null) {
      return;
    }

    final updated =
        await _runBusy<KorlixLiveConvoAgent>(
      () {
        return widget.client.saveTraining(
          agentId: agent.id,
          update: update,
        );
      },
    );

    if (!mounted || updated == null) {
      return;
    }

    _replaceAgent(updated);

    _showMessage(
      '${updated.name} training was saved '
      'as version ${updated.version}.',
    );
  }

  Future<void> _openMemoryManager(
    KorlixLiveConvoAgent agent,
  ) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xCC02070C),
      builder: (sheetContext) {
        return _KorlixAgentMemoryManagerSheet(
          client: widget.client,
          agent: agent,
        );
      },
    );

    if (!mounted || changed != true) {
      return;
    }

    await _load();

    if (!mounted) {
      return;
    }

    _showMessage(
      '${agent.name} long-term memory was updated.',
    );
  }

  Future<void> _openCustomAgentCreator() async {
    final draft =
        await showModalBottomSheet<
            KorlixLiveConvoCustomAgentDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xCC02070C),
      builder: (sheetContext) {
        return const _KorlixCustomAgentCreatorSheet();
      },
    );

    if (!mounted || draft == null) {
      return;
    }

    final created =
        await _runBusy<KorlixLiveConvoAgent>(
      () {
        return widget.client.createCustomAgent(
          draft,
        );
      },
    );

    if (!mounted || created == null) {
      return;
    }

    _replaceAgent(created);

    _showMessage(
      '${created.name} was created. '
      'Select Use Agent to activate it.',
    );
  }

  Future<void> _openVersionHistory(
    KorlixLiveConvoAgent agent,
  ) async {
    final versions = await _runBusy<
        List<KorlixLiveConvoAgentVersion>>(
      () {
        return widget.client.loadVersions(
          agentId: agent.id,
        );
      },
    );

    if (!mounted || versions == null) {
      return;
    }

    if (versions.isEmpty) {
      _showMessage(
        '${agent.name} has no saved training '
        'versions yet.',
      );

      return;
    }

    final selectedVersion =
        await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xCC02070C),
      builder: (sheetContext) {
        return _KorlixAgentVersionHistorySheet(
          agent: agent,
          versions: versions,
        );
      },
    );

    if (!mounted || selectedVersion == null) {
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Restore training version?',
      message:
          'Restore ${agent.name} version '
          '$selectedVersion as a new active version? '
          'The current version will remain available '
          'in the history.',
      confirmLabel: 'Restore Version',
    );

    if (!mounted || !confirmed) {
      return;
    }

    final restored =
        await _runBusy<KorlixLiveConvoAgent>(
      () {
        return widget.client.restoreVersion(
          agentId: agent.id,
          version: selectedVersion,
          confirmed: true,
        );
      },
    );

    if (!mounted || restored == null) {
      return;
    }

    _replaceAgent(restored);

    _showMessage(
      '${restored.name} version '
      '$selectedVersion was restored '
      'as version ${restored.version}.',
    );
  }

  Future<void> _resetOrDeleteAgent(
    KorlixLiveConvoAgent agent,
  ) async {
    final deletingCustom = agent.isCustom;

    final confirmed = await _confirmAction(
      title: deletingCustom
          ? 'Delete custom agent?'
          : 'Reset personal training?',
      message: deletingCustom
          ? 'Delete ${agent.name}, its private '
              'training history, and all of its '
              'long-term memories? This cannot '
              'be undone.'
          : 'Remove your personal training, '
              'training history, and long-term '
              'memories from ${agent.name}? '
              'The protected built-in agent '
              'will remain available.',
      confirmLabel: deletingCustom
          ? 'Delete Agent'
          : 'Reset Agent',
      destructive: true,
    );

    if (!mounted || !confirmed) {
      return;
    }

    final completed = await _runBusy<bool>(
      () async {
        await widget.client.deleteOrResetAgent(
          agentId: agent.id,
          confirmed: true,
        );

        return true;
      },
    );

    if (!mounted || completed != true) {
      return;
    }

    if (deletingCustom) {
      setState(() {
        _selectedAgentId = 'general';
      });
    }

    await _load();

    if (!mounted) {
      return;
    }

    _showMessage(
      deletingCustom
          ? '${agent.name} was deleted.'
          : '${agent.name} personal training '
              'and memory were reset.',
    );
  }
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 920,
            maxHeight: screenSize.height * 0.94,
          ),
          margin: const EdgeInsets.only(top: 24),
          decoration: const BoxDecoration(
            color: Color(0xFF041019),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 34,
                offset: Offset(0, -8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildHeader(),
                if (_busy)
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: Color(0xFF69D9E8),
                    backgroundColor: Color(0xFF123A47),
                  ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                      bottom: 18 + bottomInset,
                    ),
                    children: [
                      _buildModelProofCard(),
                      _buildPersistenceNotice(),
                      _buildErrorBanner(),
                      _buildAgentCatalog(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KorlixAgentBadge extends StatelessWidget {
  const _KorlixAgentBadge({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.78),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

const List<String> _korlixAgentAllToolIds =
    <String>[
  'general_chat',
  'live_docs',
  'file_analysis',
  'image_generation',
  'image_improvement',
  'camera',
  'memory',
  'agent_training',
];

String _korlixAgentToolLabel(
  String toolId,
) {
  switch (toolId) {
    case 'general_chat':
      return 'General conversation';

    case 'live_docs':
      return 'LIVE DOCS';

    case 'file_analysis':
      return 'File analysis';

    case 'image_generation':
      return 'Image generation';

    case 'image_improvement':
      return 'Improve picture';

    case 'camera':
      return 'Camera';

    case 'memory':
      return 'Long-term memory';

    case 'agent_training':
      return 'Agent training';

    default:
      final words = toolId
          .split('_')
          .where(
            (word) => word.trim().isNotEmpty,
          )
          .map(
            (word) =>
                '${word[0].toUpperCase()}'
                '${word.substring(1)}',
          );

      return words.join(' ');
  }
}

String _korlixAgentToolDescription(
  String toolId,
) {
  switch (toolId) {
    case 'general_chat':
      return 'Normal LIVE CONVO conversation and reasoning.';

    case 'live_docs':
      return 'Plan, create, revise, and explain reports and documents.';

    case 'file_analysis':
      return 'Use authenticated source files submitted by the user.';

    case 'image_generation':
      return 'Create new graphics through the approved image tool.';

    case 'image_improvement':
      return 'Improve or transform an image supplied by the user.';

    case 'camera':
      return 'Accept user-authorized camera and image input.';

    case 'memory':
      return 'Load and save this agent’s private approved memories.';

    case 'agent_training':
      return 'Publish user-confirmed instructions for this agent.';

    default:
      return 'Authorized Korlix capability.';
  }
}

class _KorlixAgentTrainingSheet
    extends StatefulWidget {
  const _KorlixAgentTrainingSheet({
    required this.agent,
  });

  final KorlixLiveConvoAgent agent;

  @override
  State<_KorlixAgentTrainingSheet>
  createState() {
    return _KorlixAgentTrainingSheetState();
  }
}

class _KorlixAgentTrainingSheetState
    extends State<_KorlixAgentTrainingSheet> {
  late final TextEditingController
      _instructionsController;

  late final List<String> _availableTools;
  late final Set<String> _selectedTools;

  late bool _memoryEnabled;

  bool _confirmed = false;

  String? _validationMessage;

  @override
  void initState() {
    super.initState();

    _instructionsController =
        TextEditingController();

    _memoryEnabled =
        widget.agent.memoryEnabled;

    final protectedFallback =
        KorlixLiveConvoAgent.fallbackForId(
      widget.agent.id,
    );

    final allowedTools =
        widget.agent.isBuiltIn
            ? protectedFallback.toolIds
            : _korlixAgentAllToolIds;

    _availableTools =
        List<String>.unmodifiable(
      _korlixAgentAllToolIds.where(
        allowedTools.contains,
      ),
    );

    _selectedTools =
        widget.agent.toolIds
            .where(
              _availableTools.contains,
            )
            .toSet();

    if (_availableTools.contains(
      'general_chat',
    )) {
      _selectedTools.add(
        'general_chat',
      );
    }

    if (_availableTools.contains(
      'agent_training',
    )) {
      _selectedTools.add(
        'agent_training',
      );
    }

    if (_memoryEnabled &&
        _availableTools.contains(
          'memory',
        )) {
      _selectedTools.add(
        'memory',
      );
    } else {
      _selectedTools.remove(
        'memory',
      );
    }
  }

  @override
  void dispose() {
    _instructionsController.dispose();

    super.dispose();
  }

  bool _isRequiredTool(
    String toolId,
  ) {
    if (toolId == 'general_chat' ||
        toolId == 'agent_training') {
      return true;
    }

    return toolId == 'memory' &&
        _memoryEnabled;
  }

  void _toggleTool(
    String toolId,
    bool selected,
  ) {
    if (toolId == 'memory') {
      _toggleMemory(selected);
      return;
    }

    if (!selected &&
        _isRequiredTool(toolId)) {
      return;
    }

    setState(() {
      if (selected) {
        _selectedTools.add(toolId);
      } else {
        _selectedTools.remove(toolId);
      }

      _validationMessage = null;
    });
  }

  void _toggleMemory(
    bool enabled,
  ) {
    setState(() {
      _memoryEnabled = enabled;

      if (enabled &&
          _availableTools.contains(
            'memory',
          )) {
        _selectedTools.add(
          'memory',
        );
      } else {
        _selectedTools.remove(
          'memory',
        );
      }

      _validationMessage = null;
    });
  }

  void _submitTraining() {
    final instructions =
        _instructionsController.text.trim();

    if (instructions.isEmpty) {
      setState(() {
        _validationMessage =
            'Enter the new instructions '
            'you want this agent to learn.';
      });

      return;
    }

    if (!_confirmed) {
      setState(() {
        _validationMessage =
            'Confirm that these instructions '
            'may be saved as long-term agent training.';
      });

      return;
    }

    final selectedTools =
        Set<String>.from(
      _selectedTools,
    )
          ..add('general_chat')
          ..add('agent_training');

    if (_memoryEnabled &&
        _availableTools.contains(
          'memory',
        )) {
      selectedTools.add('memory');
    } else {
      selectedTools.remove('memory');
    }

    final orderedTools =
        _availableTools
            .where(
              selectedTools.contains,
            )
            .toList(
              growable: false,
            );

    Navigator.of(context).pop(
      KorlixLiveConvoAgentTrainingUpdate(
        instructions: instructions,
        confirmed: true,
        toolIds: orderedTools,
        memoryEnabled: _memoryEnabled,
        source: 'agent_hub_training',
      ),
    );
  }

  InputDecoration _trainingDecoration({
    required String label,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor:
          const Color(0xFF071722),
      labelStyle:
          const TextStyle(
        color: Color(0xFF8CDDE8),
        fontWeight: FontWeight.w800,
      ),
      hintStyle:
          const TextStyle(
        color: Color(0xFF718A96),
      ),
      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            const BorderSide(
          color: Color(0xFF244D5C),
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            const BorderSide(
          color: Color(0xFF69D9E8),
          width: 1.6,
        ),
      ),
      errorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            const BorderSide(
          color: Color(0xFFFF7185),
        ),
      ),
    );
  }
  Widget _buildTrainingHeader(
    Color accent,
  ) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(16),
            color:
                accent.withValues(
              alpha: 0.14,
            ),
            border: Border.all(
              color:
                  accent.withValues(
                alpha: 0.72,
              ),
            ),
          ),
          child: Icon(
            korlixLiveConvoAgentIcon(
              widget.agent.iconName,
            ),
            color: accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'TRAIN ${widget.agent.name.toUpperCase()}',
                style: const TextStyle(
                  color:
                      Color(0xFFF0F7F8),
                  fontSize: 19,
                  fontWeight:
                      FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add private instructions and '
                'choose the tools this agent '
                'may use.',
                style: const TextStyle(
                  color:
                      Color(0xFFA9C6CF),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close training',
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.close_rounded,
          ),
          color:
              const Color(0xFFC7D7DC),
        ),
      ],
    );
  }

  Widget _buildProtectedMissionNotice(
    Color accent,
  ) {
    final isBuiltIn =
        widget.agent.isBuiltIn;

    return Container(
      padding:
          const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(17),
        color:
            const Color(0xFF081B25),
        border: Border.all(
          color:
              accent.withValues(
            alpha: 0.52,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            isBuiltIn
                ? Icons
                    .verified_user_rounded
                : Icons
                    .smart_toy_rounded,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  isBuiltIn
                      ? 'Protected built-in mission'
                      : 'Custom-agent mission',
                  style: TextStyle(
                    color: accent,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.agent.mission,
                  style: const TextStyle(
                    color:
                        Color(0xFFD8E7EA),
                    height: 1.4,
                  ),
                ),
                if (isBuiltIn) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Personal training supplements '
                    'this mission. It cannot replace '
                    'Korlix safety rules or unlock '
                    'tools that this agent is not '
                    'authorized to use.',
                    style: TextStyle(
                      color:
                          Color(0xFFA9C6CF),
                      height: 1.35,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTraining() {
    final training =
        widget.agent
            .trainingInstructions
            .trim();

    if (training.isEmpty) {
      return Container(
        padding:
            const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(16),
          color:
              const Color(0xFF071722),
          border: Border.all(
            color:
                const Color(0xFF244D5C),
          ),
        ),
        child: const Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              Icons
                  .school_outlined,
              color:
                  Color(0xFF8CDDE8),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No personal training has been '
                'published for this agent yet.',
                style: TextStyle(
                  color:
                      Color(0xFFBBD0D6),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color:
            const Color(0xFF0B2A24),
        border: Border.all(
          color:
              const Color(0xFF3A9778),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons
                    .check_circle_rounded,
                color:
                    Color(0xFF62D6A7),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'CURRENT PUBLISHED TRAINING '
                  '· VERSION '
                  '${widget.agent.version}',
                  style: const TextStyle(
                    color:
                        Color(0xFF62D6A7),
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            training,
            style: const TextStyle(
              color:
                  Color(0xFFD8E7EA),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersistenceWarning() {
    if (widget.agent.persistenceConfigured) {
      return const SizedBox.shrink();
    }

    return Container(
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color:
            const Color(0xFF332916),
        border: Border.all(
          color:
              const Color(0xFFF2C14E),
        ),
      ),
      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.storage_rounded,
            color:
                Color(0xFFF2C14E),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Agent selection is available, '
              'but training cannot be saved '
              'until the included Supabase '
              'long-term-memory migration '
              'has been reviewed and applied.',
              style: TextStyle(
                color:
                    Color(0xFFFFE7A3),
                height: 1.4,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryControl(
    Color accent,
  ) {
    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        13,
        10,
        10,
        10,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color:
              const Color(0xFF244D5C),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _memoryEnabled
                ? Icons
                    .psychology_alt_rounded
                : Icons
                    .memory_outlined,
            color: _memoryEnabled
                ? accent
                : const Color(
                    0xFF8299A2,
                  ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Long-term memory',
                  style: TextStyle(
                    color:
                        Color(0xFFF0F7F8),
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Allows this agent to load '
                  'and save private user-approved '
                  'memories across sessions.',
                  style: TextStyle(
                    color:
                        Color(0xFFA9C6CF),
                    height: 1.3,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: _memoryEnabled,
            onChanged:
                _availableTools.contains(
              'memory',
            )
                ? _toggleMemory
                : null,
            activeThumbColor: accent,
            activeTrackColor:
                accent.withValues(
              alpha: 0.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolPermissions(
    Color accent,
  ) {
    final tools = _availableTools
        .where(
          (toolId) =>
              toolId != 'memory',
        )
        .toList(
          growable: false,
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(18),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color:
              const Color(0xFF244D5C),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (
            var index = 0;
            index < tools.length;
            index += 1
          ) ...[
            Builder(
              builder: (context) {
                final toolId =
                    tools[index];

                final required =
                    _isRequiredTool(
                  toolId,
                );

                final selected =
                    _selectedTools
                        .contains(
                  toolId,
                );

                return CheckboxListTile(
                  value: selected,
                  onChanged: required
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }

                          _toggleTool(
                            toolId,
                            value,
                          );
                        },
                  controlAffinity:
                      ListTileControlAffinity
                          .leading,
                  activeColor: accent,
                  checkColor:
                      const Color(
                    0xFF03110E,
                  ),
                  contentPadding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  title: Text(
                    _korlixAgentToolLabel(
                      toolId,
                    ),
                    style: TextStyle(
                      color: selected
                          ? const Color(
                              0xFFF0F7F8,
                            )
                          : const Color(
                              0xFF8299A2,
                            ),
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    required
                        ? '${_korlixAgentToolDescription(toolId)} '
                            'Required for this agent.'
                        : _korlixAgentToolDescription(
                            toolId,
                          ),
                    style: const TextStyle(
                      color:
                          Color(0xFFA9C6CF),
                      height: 1.3,
                      fontSize: 12.5,
                    ),
                  ),
                );
              },
            ),
            if (index !=
                tools.length - 1)
              const Divider(
                height: 1,
                color:
                    Color(0xFF173541),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildConsentControl() {
    return Container(
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color: _confirmed
              ? const Color(
                  0xFF62D6A7,
                )
              : const Color(
                  0xFF244D5C,
                ),
        ),
      ),
      child: CheckboxListTile(
        value: _confirmed,
        onChanged: (value) {
          setState(() {
            _confirmed =
                value == true;

            _validationMessage =
                null;
          });
        },
        controlAffinity:
            ListTileControlAffinity
                .leading,
        activeColor:
            const Color(0xFF62D6A7),
        checkColor:
            const Color(0xFF03110E),
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 3,
        ),
        title: const Text(
          'Save as long-term agent training',
          style: TextStyle(
            color:
                Color(0xFFF0F7F8),
            fontWeight:
                FontWeight.w900,
          ),
        ),
        subtitle: const Text(
          'I understand that these '
          'instructions will remain active '
          'for this agent across future '
          'sessions until I reset, replace, '
          'or restore its training.',
          style: TextStyle(
            color:
                Color(0xFFA9C6CF),
            height: 1.35,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize =
        MediaQuery.sizeOf(context);

    final bottomInset =
        MediaQuery.viewInsetsOf(
      context,
    ).bottom;

    final accent =
        korlixLiveConvoAgentAccent(
      widget.agent.accentHex,
    );

    final canSave =
        widget.agent
            .persistenceConfigured;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment:
            Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 780,
            maxHeight:
                screenSize.height *
                0.94,
          ),
          margin:
              const EdgeInsets.only(
            top: 24,
          ),
          decoration:
              const BoxDecoration(
            color:
                Color(0xFF041019),
            borderRadius:
                BorderRadius.vertical(
              top:
                  Radius.circular(28),
            ),
            boxShadow:
                <BoxShadow>[
              BoxShadow(
                color:
                    Color(0x66000000),
                blurRadius: 34,
                offset:
                    Offset(0, -8),
              ),
            ],
          ),
          clipBehavior:
              Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: ListView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior
                      .onDrag,
              padding:
                  EdgeInsets.fromLTRB(
                18,
                14,
                18,
                26 + bottomInset,
              ),
              children: [
                _buildTrainingHeader(
                  accent,
                ),
                const SizedBox(
                  height: 14,
                ),
                _buildProtectedMissionNotice(
                  accent,
                ),
                const SizedBox(
                  height: 14,
                ),
                _buildPersistenceWarning(),
                if (!widget.agent
                    .persistenceConfigured)
                  const SizedBox(
                    height: 14,
                  ),
                const Text(
                  'CURRENT TRAINING',
                  style: TextStyle(
                    color:
                        Color(0xFF8CDDE8),
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.6,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                _buildCurrentTraining(),
                const SizedBox(
                  height: 18,
                ),
                const Text(
                  'NEW TRAINING TO ADD',
                  style: TextStyle(
                    color:
                        Color(0xFF8CDDE8),
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.6,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                TextField(
                  controller:
                      _instructionsController,
                  minLines: 5,
                  maxLines: 12,
                  maxLength: 12000,
                  enabled: canSave,
                  style:
                      const TextStyle(
                    color:
                        Color(0xFFF0F7F8),
                    height: 1.4,
                  ),
                  decoration:
                      _trainingDecoration(
                    label:
                        'Instructions for '
                        '${widget.agent.name}',
                    hint:
                        'Example: Use concise '
                        'executive summaries and '
                        'place action items at '
                        'the end.',
                  ),
                  onChanged: (_) {
                    if (_validationMessage !=
                        null) {
                      setState(() {
                        _validationMessage =
                            null;
                      });
                    }
                  },
                ),
                const SizedBox(
                  height: 16,
                ),
                const Text(
                  'MEMORY',
                  style: TextStyle(
                    color:
                        Color(0xFF8CDDE8),
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.6,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                _buildMemoryControl(
                  accent,
                ),
                const SizedBox(
                  height: 18,
                ),
                const Text(
                  'AUTHORIZED TOOLS',
                  style: TextStyle(
                    color:
                        Color(0xFF8CDDE8),
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.6,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                const Text(
                  'Built-in agents may use '
                  'only their protected tool '
                  'set. Custom agents may use '
                  'only tools explicitly enabled '
                  'here.',
                  style: TextStyle(
                    color:
                        Color(0xFFA9C6CF),
                    height: 1.35,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(
                  height: 9,
                ),
                _buildToolPermissions(
                  accent,
                ),
                const SizedBox(
                  height: 18,
                ),
                _buildConsentControl(),
                if (_validationMessage !=
                    null) ...[
                  const SizedBox(
                    height: 12,
                  ),
                  Container(
                    padding:
                        const EdgeInsets
                            .all(12),
                    decoration:
                        BoxDecoration(
                      borderRadius:
                          BorderRadius
                              .circular(14),
                      color:
                          const Color(
                        0xFF351923,
                      ),
                      border:
                          Border.all(
                        color:
                            const Color(
                          0xFFFF7185,
                        ),
                      ),
                    ),
                    child: Text(
                      _validationMessage!,
                      style:
                          const TextStyle(
                        color:
                            Color(
                          0xFFFFD8DE,
                        ),
                        fontWeight:
                            FontWeight
                                .w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(
                  height: 18,
                ),
                Row(
                  children: [
                    Expanded(
                      child:
                          OutlinedButton(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pop();
                        },
                        style:
                            OutlinedButton
                                .styleFrom(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 15,
                          ),
                        ),
                        child:
                            const Text(
                          'Cancel',
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      flex: 2,
                      child:
                          FilledButton.icon(
                        onPressed:
                            canSave
                            ? _submitTraining
                            : null,
                        style:
                            FilledButton
                                .styleFrom(
                          backgroundColor:
                              accent,
                          foregroundColor:
                              const Color(
                            0xFF03110E,
                          ),
                          disabledBackgroundColor:
                              const Color(
                            0xFF33454B,
                          ),
                          disabledForegroundColor:
                              const Color(
                            0xFF83969C,
                          ),
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 15,
                          ),
                        ),
                        icon:
                            const Icon(
                          Icons
                              .publish_rounded,
                        ),
                        label: Text(
                          canSave
                              ? 'Publish Training'
                              : 'Migration Required',
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight
                                    .w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KorlixAgentMemoryManagerSheet
    extends StatefulWidget {
  const _KorlixAgentMemoryManagerSheet({
    required this.client,
    required this.agent,
  });

  final KorlixLiveConvoAgentClient client;
  final KorlixLiveConvoAgent agent;

  @override
  State<_KorlixAgentMemoryManagerSheet>
  createState() {
    return _KorlixAgentMemoryManagerSheetState();
  }
}

class _KorlixAgentMemoryManagerSheetState
    extends State<_KorlixAgentMemoryManagerSheet> {
  List<KorlixLiveConvoAgentMemory> _memories =
      const <KorlixLiveConvoAgentMemory>[];

  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    unawaited(
      _loadMemories(),
    );
  }

  String _cleanMemoryError(
    Object error,
  ) {
    return error
        .toString()
        .replaceFirst(
          'KorlixLiveConvoAgentClientException: ',
          '',
        )
        .replaceFirst(
          'Exception: ',
          '',
        )
        .trim();
  }

  List<KorlixLiveConvoAgentMemory>
  _sortMemories(
    Iterable<KorlixLiveConvoAgentMemory> source,
  ) {
    final result =
        source.toList(
      growable: false,
    );

    result.sort(
      (left, right) {
        final importance =
            right.importance.compareTo(
          left.importance,
        );

        if (importance != 0) {
          return importance;
        }

        final rightDate =
            right.updatedAt ??
            right.createdAt;

        final leftDate =
            left.updatedAt ??
            left.createdAt;

        final rightStamp =
            rightDate
                ?.millisecondsSinceEpoch ??
            0;

        final leftStamp =
            leftDate
                ?.millisecondsSinceEpoch ??
            0;

        return rightStamp.compareTo(
          leftStamp,
        );
      },
    );

    return List<
        KorlixLiveConvoAgentMemory>.unmodifiable(
      result,
    );
  }

  Future<void> _loadMemories({
    bool showLoading = true,
  }) async {
    if (!mounted) {
      return;
    }

    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final loaded =
          await widget.client.loadMemories(
        agentId:
            widget.agent.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _memories =
            _sortMemories(
          loaded,
        );

        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error =
            _cleanMemoryError(
          error,
        );
      });
    }
  }

  Future<T?> _runMemoryBusy<T>(
    Future<T> Function() callback,
  ) async {
    if (_busy) {
      return null;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      return await callback();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              _cleanMemoryError(
            error,
          );
        });
      }

      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showMemoryMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error
              ? const Color(
                  0xFF8D3344,
                )
              : const Color(
                  0xFF17644D,
                ),
          duration:
              const Duration(
            seconds: 5,
          ),
        ),
      );
  }

  Future<bool> _confirmMemoryAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result =
        await showDialog<bool>(
      context: context,
      barrierDismissible:
          !_busy,
      builder: (dialogContext) {
        final confirmColor =
            destructive
            ? const Color(
                0xFFFF7185,
              )
            : const Color(
                0xFF62D6A7,
              );

        return AlertDialog(
          backgroundColor:
              const Color(
            0xFF071722,
          ),
          title: Text(
            title,
            style:
                const TextStyle(
              color:
                  Color(
                0xFFF0F7F8,
              ),
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          content: Text(
            message,
            style:
                const TextStyle(
              color:
                  Color(
                0xFFBBD0D6,
              ),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child:
                  const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              style:
                  FilledButton
                      .styleFrom(
                backgroundColor:
                    confirmColor,
                foregroundColor:
                    const Color(
                  0xFF03110E,
                ),
              ),
              child: Text(
                confirmLabel,
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  void _closeMemoryManager() {
    if (_busy) {
      return;
    }

    Navigator.of(context).pop(
      _changed,
    );
  }

  Future<void> _openAddMemory() async {
    if (!widget.agent
        .persistenceConfigured) {
      _showMemoryMessage(
        'Apply the included Supabase '
        'long-term-memory migration before '
        'saving memories.',
        error: true,
      );

      return;
    }

    if (!widget.agent.memoryEnabled) {
      _showMemoryMessage(
        'Long-term memory is disabled for '
        '${widget.agent.name}. Enable it in '
        'Train Agent first.',
        error: true,
      );

      return;
    }

    final draft =
        await showModalBottomSheet<
            KorlixLiveConvoMemoryDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor:
          Colors.transparent,
      barrierColor:
          const Color(
        0xCC02070C,
      ),
      builder: (sheetContext) {
        return _KorlixAgentMemoryDraftSheet(
          agent:
              widget.agent,
        );
      },
    );

    if (!mounted || draft == null) {
      return;
    }

    final saved =
        await _runMemoryBusy<
            KorlixLiveConvoAgentMemory>(
      () {
        return widget.client.saveMemory(
          agentId:
              widget.agent.id,
          draft: draft,
        );
      },
    );

    if (!mounted || saved == null) {
      return;
    }

    setState(() {
      _changed = true;

      _memories =
          _sortMemories(
        <KorlixLiveConvoAgentMemory>[
          for (final memory
              in _memories)
            if (memory.id !=
                saved.id)
              memory,
          saved,
        ],
      );
    });

    _showMemoryMessage(
      'Memory saved privately for '
      '${widget.agent.name}.',
    );
  }

  Future<void> _deleteMemory(
    KorlixLiveConvoAgentMemory memory,
  ) async {
    final label =
        memory.label.trim().isEmpty
        ? memory.content
        : memory.label;

    final preview =
        label.length <= 120
        ? label
        : '${label.substring(0, 117)}...';

    final confirmed =
        await _confirmMemoryAction(
      title: 'Delete this memory?',
      message:
          'Remove “$preview” from '
          '${widget.agent.name} long-term '
          'memory? This cannot be undone.',
      confirmLabel: 'Delete Memory',
      destructive: true,
    );

    if (!mounted || !confirmed) {
      return;
    }

    final completed =
        await _runMemoryBusy<bool>(
      () async {
        await widget.client.deleteMemory(
          agentId:
              widget.agent.id,
          memoryId:
              memory.id,
          confirmed: true,
        );

        return true;
      },
    );

    if (!mounted ||
        completed != true) {
      return;
    }

    setState(() {
      _changed = true;

      _memories =
          List<
              KorlixLiveConvoAgentMemory>.unmodifiable(
        _memories.where(
          (candidate) =>
              candidate.id !=
              memory.id,
        ),
      );
    });

    _showMemoryMessage(
      'Memory deleted.',
    );
  }

  Future<void> _clearAllMemories() async {
    if (_memories.isEmpty) {
      _showMemoryMessage(
        '${widget.agent.name} has no '
        'saved memories to clear.',
      );

      return;
    }

    final confirmed =
        await _confirmMemoryAction(
      title: 'Clear all memories?',
      message:
          'Delete all ${_memories.length} '
          'private long-term memories from '
          '${widget.agent.name}? Personal '
          'training instructions will remain. '
          'This cannot be undone.',
      confirmLabel: 'Clear All Memories',
      destructive: true,
    );

    if (!mounted || !confirmed) {
      return;
    }

    final completed =
        await _runMemoryBusy<bool>(
      () async {
        await widget.client.clearMemories(
          agentId:
              widget.agent.id,
          confirmed: true,
        );

        return true;
      },
    );

    if (!mounted ||
        completed != true) {
      return;
    }

    setState(() {
      _changed = true;

      _memories =
          const <
              KorlixLiveConvoAgentMemory>[];
    });

    _showMemoryMessage(
      '${widget.agent.name} memories '
      'were cleared.',
    );
  }

  Future<void> _forgetMatchingMemories() async {
    if (_memories.isEmpty) {
      _showMemoryMessage(
        '${widget.agent.name} has no '
        'saved memories to search.',
      );

      return;
    }

    final controller =
        TextEditingController();

    final query =
        await showDialog<String>(
      context: context,
      barrierDismissible:
          !_busy,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(
            0xFF071722,
          ),
          title:
              const Text(
            'Forget matching memories',
            style: TextStyle(
              color:
                  Color(
                0xFFF0F7F8,
              ),
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          content: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Describe the saved fact, '
                'preference, goal, correction, '
                'or style that this agent '
                'should forget.',
                style: TextStyle(
                  color:
                      Color(
                    0xFFBBD0D6,
                  ),
                  height: 1.4,
                ),
              ),
              const SizedBox(
                height: 14,
              ),
              TextField(
                controller:
                    controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: 400,
                style:
                    const TextStyle(
                  color:
                      Color(
                    0xFFF0F7F8,
                  ),
                ),
                decoration:
                    InputDecoration(
                  labelText:
                      'Memory to forget',
                  hintText:
                      'Example: My old report '
                      'color preference',
                  filled: true,
                  fillColor:
                      const Color(
                    0xFF041019,
                  ),
                  enabledBorder:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      15,
                    ),
                    borderSide:
                        const BorderSide(
                      color:
                          Color(
                        0xFF244D5C,
                      ),
                    ),
                  ),
                  focusedBorder:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      15,
                    ),
                    borderSide:
                        const BorderSide(
                      color:
                          Color(
                        0xFFFF7185,
                      ),
                      width: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                height: 6,
              ),
              const Text(
                'All active memories containing '
                'the matching text may be removed.',
                style: TextStyle(
                  color:
                      Color(
                    0xFFFFC2CB,
                  ),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child:
                  const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                final clean =
                    controller.text
                        .trim();

                if (clean.isEmpty) {
                  return;
                }

                Navigator.of(
                  dialogContext,
                ).pop(clean);
              },
              style:
                  FilledButton
                      .styleFrom(
                backgroundColor:
                    const Color(
                  0xFFFF7185,
                ),
                foregroundColor:
                    const Color(
                  0xFF25030A,
                ),
              ),
              icon:
                  const Icon(
                Icons
                    .delete_sweep_rounded,
              ),
              label:
                  const Text(
                'Forget Matches',
                style: TextStyle(
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!mounted ||
        query == null ||
        query.trim().isEmpty) {
      return;
    }

    final removed =
        await _runMemoryBusy<int>(
      () {
        return widget.client.forgetMemories(
          agentId:
              widget.agent.id,
          query:
              query.trim(),
          confirmed: true,
        );
      },
    );

    if (!mounted || removed == null) {
      return;
    }

    if (removed <= 0) {
      _showMemoryMessage(
        'No matching memories were found.',
      );

      return;
    }

    _changed = true;

    await _loadMemories(
      showLoading: false,
    );

    if (!mounted) {
      return;
    }

    _showMemoryMessage(
      removed == 1
          ? '1 matching memory was forgotten.'
          : '$removed matching memories '
              'were forgotten.',
    );
  }
  String _memoryKindLabel(
    String kind,
  ) {
    switch (kind.trim().toLowerCase()) {
      case 'fact':
        return 'Fact';

      case 'goal':
        return 'Goal';

      case 'style':
        return 'Style';

      case 'example':
        return 'Example';

      case 'correction':
        return 'Correction';

      case 'vocabulary':
        return 'Vocabulary';

      case 'preference':
      default:
        return 'Preference';
    }
  }

  IconData _memoryKindIcon(
    String kind,
  ) {
    switch (kind.trim().toLowerCase()) {
      case 'fact':
        return Icons.fact_check_rounded;

      case 'goal':
        return Icons.flag_rounded;

      case 'style':
        return Icons.tune_rounded;

      case 'example':
        return Icons.lightbulb_rounded;

      case 'correction':
        return Icons.rule_rounded;

      case 'vocabulary':
        return Icons.translate_rounded;

      case 'preference':
      default:
        return Icons.favorite_rounded;
    }
  }

  Color _memoryKindColor(
    String kind,
  ) {
    switch (kind.trim().toLowerCase()) {
      case 'fact':
        return const Color(0xFF69D9E8);

      case 'goal':
        return const Color(0xFFF2C14E);

      case 'style':
        return const Color(0xFFB794F4);

      case 'example':
        return const Color(0xFFFFB86B);

      case 'correction':
        return const Color(0xFFFF7185);

      case 'vocabulary':
        return const Color(0xFF7CC4FF);

      case 'preference':
      default:
        return const Color(0xFF62D6A7);
    }
  }

  String _memorySourceLabel(
    String source,
  ) {
    final clean = source
        .trim()
        .replaceAll('_', ' ');

    if (clean.isEmpty) {
      return 'User confirmed';
    }

    return clean
        .split(' ')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
          (word) =>
              '${word[0].toUpperCase()}'
              '${word.substring(1)}',
        )
        .join(' ');
  }

  String _formatMemoryDate(
    DateTime? value,
  ) {
    if (value == null) {
      return '';
    }

    final local = value.toLocal();
    final hour = local.hour % 12 == 0
        ? 12
        : local.hour % 12;

    final minute = local.minute
        .toString()
        .padLeft(2, '0');

    final period = local.hour >= 12
        ? 'PM'
        : 'AM';

    return '${local.month}/${local.day}/${local.year} '
        '$hour:$minute $period';
  }

  Widget _buildMemoryHeader(
    Color accent,
  ) {
    final memoryCount = _memories.length;

    final countLabel = memoryCount == 1
        ? '1 saved memory'
        : '$memoryCount saved memories';

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        18,
        12,
        12,
        10,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(16),
              color: accent.withValues(
                alpha: 0.14,
              ),
              border: Border.all(
                color: accent.withValues(
                  alpha: 0.72,
                ),
              ),
            ),
            child: Icon(
              Icons.psychology_alt_rounded,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.agent.name.toUpperCase()} MEMORY',
                  style: const TextStyle(
                    color: Color(0xFFF0F7F8),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  countLabel,
                  style: const TextStyle(
                    color: Color(0xFFA9C6CF),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close memory manager',
            onPressed: _busy
                ? null
                : _closeMemoryManager,
            icon: const Icon(
              Icons.close_rounded,
            ),
            color:
                const Color(0xFFC7D7DC),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryStatusNotice() {
    final persistenceReady =
        widget.agent.persistenceConfigured;

    final memoryEnabled =
        widget.agent.memoryEnabled;

    final ready =
        persistenceReady && memoryEnabled;

    final color = ready
        ? const Color(0xFF62D6A7)
        : const Color(0xFFF2C14E);

    final message = !persistenceReady
        ? 'Apply the included Supabase migration '
            'before saving or deleting private '
            'long-term memories.'
        : !memoryEnabled
            ? 'Long-term memory is disabled for '
                '${widget.agent.name}. Open Train '
                'Agent to enable it.'
            : 'These records are private to '
                '${widget.agent.name} and are loaded '
                'only when this agent is active.';

    return Container(
      margin:
          const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color: ready
            ? const Color(0xFF0B2A24)
            : const Color(0xFF332916),
        border: Border.all(
          color: color,
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            ready
                ? Icons.lock_rounded
                : Icons.info_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFD8E7EA),
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryErrorBanner() {
    final error = _error?.trim() ?? '';

    if (error.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin:
          const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color:
            const Color(0xFF351923),
        border: Border.all(
          color:
              const Color(0xFFFF7185),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color:
                Color(0xFFFF8B9B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color:
                    Color(0xFFFFD8DE),
                height: 1.35,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Retry memory load',
            onPressed: _busy
                ? null
                : () {
                    unawaited(
                      _loadMemories(),
                    );
                  },
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            color:
                const Color(0xFFFFB2BE),
          ),
        ],
      ),
    );
  }

  Widget _buildImportanceIndicator({
    required int importance,
    required Color color,
  }) {
    final safeImportance = importance < 1
        ? 1
        : importance > 5
            ? 5
            : importance;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 1; index <= 5; index += 1)
          Padding(
            padding: EdgeInsets.only(
              right: index == 5 ? 0 : 2,
            ),
            child: Icon(
              index <= safeImportance
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              size: 15,
              color: index <= safeImportance
                  ? color
                  : const Color(0xFF607680),
            ),
          ),
      ],
    );
  }

  Widget _buildMemoryTag(
    String tag,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFF102B38),
        border: Border.all(
          color: const Color(0xFF28596A),
        ),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          color: Color(0xFFB7D7DE),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMemoryCard(
    KorlixLiveConvoAgentMemory memory,
  ) {
    final kindColor = _memoryKindColor(
      memory.kind,
    );

    final cleanLabel = memory.label.trim();

    final title = cleanLabel.isEmpty
        ? _memoryKindLabel(memory.kind)
        : cleanLabel;

    final dateLabel = _formatMemoryDate(
      memory.updatedAt ?? memory.createdAt,
    );

    final sourceLabel = _memorySourceLabel(
      memory.source,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF071722),
        border: Border.all(
          color: kindColor.withValues(
            alpha: 0.52,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: kindColor.withValues(
                    alpha: 0.15,
                  ),
                  border: Border.all(
                    color: kindColor.withValues(
                      alpha: 0.68,
                    ),
                  ),
                ),
                child: Icon(
                  _memoryKindIcon(memory.kind),
                  color: kindColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF0F7F8),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment:
                          WrapCrossAlignment.center,
                      children: [
                        _KorlixAgentBadge(
                          text: _memoryKindLabel(
                            memory.kind,
                          ).toUpperCase(),
                          color: kindColor,
                        ),
                        if (memory.sensitive)
                          const _KorlixAgentBadge(
                            text: 'SENSITIVE',
                            color: Color(0xFFFFB86B),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete memory',
                onPressed: _busy
                    ? null
                    : () {
                        unawaited(
                          _deleteMemory(memory),
                        );
                      },
                icon: const Icon(
                  Icons.delete_outline_rounded,
                ),
                color: const Color(0xFFFF8B9B),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            memory.content,
            style: const TextStyle(
              color: Color(0xFFD8E7EA),
              height: 1.45,
              fontSize: 14,
            ),
          ),
          if (memory.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final tag in memory.tags)
                  _buildMemoryTag(tag),
              ],
            ),
          ],
          const SizedBox(height: 13),
          const Divider(
            height: 1,
            color: Color(0xFF173541),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 12,
            runSpacing: 9,
            crossAxisAlignment:
                WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Importance',
                    style: TextStyle(
                      color: Color(0xFF8FA8B1),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 7),
                  _buildImportanceIndicator(
                    importance: memory.importance,
                    color: kindColor,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                    color: Color(0xFF8FA8B1),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    sourceLabel,
                    style: const TextStyle(
                      color: Color(0xFF8FA8B1),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (dateLabel.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: Color(0xFF8FA8B1),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        color: Color(0xFF8FA8B1),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryActions(
    Color accent,
  ) {
    final persistenceReady =
        widget.agent.persistenceConfigured;

    final memoryEnabled =
        widget.agent.memoryEnabled;

    final canAdd =
        persistenceReady &&
        memoryEnabled &&
        !_busy;

    final hasMemories =
        _memories.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        14,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: canAdd
                ? () {
                    unawaited(
                      _openAddMemory(),
                    );
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor:
                  const Color(0xFF03110E),
              disabledBackgroundColor:
                  const Color(0xFF33454B),
              disabledForegroundColor:
                  const Color(0xFF83969C),
              padding:
                  const EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 16,
              ),
            ),
            icon: const Icon(
              Icons.add_rounded,
            ),
            label: Text(
              !persistenceReady
                  ? 'Migration Required'
                  : !memoryEnabled
                      ? 'Enable Memory First'
                      : 'Add Confirmed Memory',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _busy || !hasMemories
                    ? null
                    : () {
                        unawaited(
                          _forgetMatchingMemories(),
                        );
                      },
                icon: const Icon(
                  Icons.search_off_rounded,
                ),
                label: const Text(
                  'Forget Matching',
                ),
              ),
              TextButton.icon(
                onPressed:
                    _busy || !hasMemories
                    ? null
                    : () {
                        unawaited(
                          _clearAllMemories(),
                        );
                      },
                style: TextButton.styleFrom(
                  foregroundColor:
                      const Color(0xFFFF8B9B),
                ),
                icon: const Icon(
                  Icons.delete_sweep_rounded,
                ),
                label: const Text(
                  'Clear All',
                ),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        unawaited(
                          _loadMemories(),
                        );
                      },
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: const Text(
                  'Refresh',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyMemoryState(
    Color accent,
  ) {
    final persistenceReady =
        widget.agent.persistenceConfigured;

    final memoryEnabled =
        widget.agent.memoryEnabled;

    final title = !persistenceReady
        ? 'Memory setup is required'
        : !memoryEnabled
            ? 'Long-term memory is disabled'
            : 'No saved memories yet';

    final message = !persistenceReady
        ? 'Apply the included Supabase migration, '
            'then reopen this memory manager.'
        : !memoryEnabled
            ? 'Open Train Agent and enable long-term '
                'memory before adding private records.'
            : 'Add a confirmed preference, fact, goal, '
                'style, example, correction, or vocabulary '
                'record for ${widget.agent.name}.';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(20),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color: accent.withValues(
            alpha: 0.46,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(
                alpha: 0.13,
              ),
              border: Border.all(
                color: accent.withValues(
                  alpha: 0.62,
                ),
              ),
            ),
            child: Icon(
              memoryEnabled
                  ? Icons.psychology_alt_rounded
                  : Icons.memory_outlined,
              color: accent,
              size: 29,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF0F7F8),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFA9C6CF),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCollection(
    Color accent,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          30,
          16,
          30,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Color(0xFF69D9E8),
              ),
              SizedBox(height: 13),
              Text(
                'Loading private memories…',
                style: TextStyle(
                  color: Color(0xFFA9C6CF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_memories.isEmpty) {
      return _buildEmptyMemoryState(
        accent,
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(
            16,
            2,
            16,
            9,
          ),
          child: Text(
            _memories.length == 1
                ? 'SAVED MEMORY'
                : 'SAVED MEMORIES',
            style: const TextStyle(
              color: Color(0xFF8CDDE8),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              fontSize: 12,
            ),
          ),
        ),
        for (final memory in _memories)
          _buildMemoryCard(memory),
      ],
    );
  }

  Widget _buildMemoryPrivacyFooter(
    Color accent,
  ) {
    final statusMessage = _changed
        ? 'Your confirmed memory changes are saved. '
            'Reload the active agent to use the latest records.'
        : 'Only memories you explicitly confirm are saved. '
            'Each record remains private to this agent.';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        16,
        11,
        12,
        11,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF06131C),
        border: Border(
          top: BorderSide(
            color: Color(0xFF173541),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _changed
                ? Icons.cloud_done_rounded
                : Icons.lock_outline_rounded,
            color: _changed
                ? const Color(0xFF62D6A7)
                : accent,
            size: 21,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              statusMessage,
              style: const TextStyle(
                color: Color(0xFFA9C6CF),
                height: 1.35,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : _closeMemoryManager,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor:
                  const Color(0xFF03110E),
              disabledBackgroundColor:
                  const Color(0xFF33454B),
              disabledForegroundColor:
                  const Color(0xFF83969C),
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 12,
              ),
            ),
            icon: const Icon(
              Icons.check_rounded,
              size: 19,
            ),
            label: const Text(
              'Done',
              style: TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize =
        MediaQuery.sizeOf(context);

    final bottomInset =
        MediaQuery.viewInsetsOf(
      context,
    ).bottom;

    final accent =
        korlixLiveConvoAgentAccent(
      widget.agent.accentHex,
    );

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment:
            Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 860,
            maxHeight:
                screenSize.height * 0.94,
          ),
          margin: const EdgeInsets.only(
            top: 24,
          ),
          decoration:
              const BoxDecoration(
            color: Color(0xFF041019),
            borderRadius:
                BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 34,
                offset: Offset(0, -8),
              ),
            ],
          ),
          clipBehavior:
              Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildMemoryHeader(
                  accent,
                ),
                if (_busy)
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color:
                        Color(0xFF69D9E8),
                    backgroundColor:
                        Color(0xFF123A47),
                  ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior
                            .onDrag,
                    padding: EdgeInsets.only(
                      bottom:
                          18 + bottomInset,
                    ),
                    children: [
                      _buildMemoryStatusNotice(),
                      _buildMemoryErrorBanner(),
                      _buildMemoryActions(
                        accent,
                      ),
                      _buildMemoryCollection(
                        accent,
                      ),
                      Container(
                        margin:
                            const EdgeInsets
                                .fromLTRB(
                          16,
                          4,
                          16,
                          16,
                        ),
                        padding:
                            const EdgeInsets
                                .all(13),
                        decoration:
                            BoxDecoration(
                          borderRadius:
                              BorderRadius
                                  .circular(16),
                          color:
                              const Color(
                            0xFF081B25,
                          ),
                          border:
                              Border.all(
                            color:
                                const Color(
                              0xFF244D5C,
                            ),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Icon(
                              Icons
                                  .verified_user_outlined,
                              color:
                                  Color(
                                0xFF8CDDE8,
                              ),
                              size: 21,
                            ),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Agent memories are '
                                'lower-priority user '
                                'data. They cannot '
                                'override Korlix safety, '
                                'privacy, authorization, '
                                'tool, or confirmation '
                                'rules.',
                                style: TextStyle(
                                  color:
                                      Color(
                                    0xFFA9C6CF,
                                  ),
                                  height: 1.4,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildMemoryPrivacyFooter(
                  accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> _korlixAgentMemoryKindIds =
    <String>[
  'preference',
  'fact',
  'goal',
  'style',
  'example',
  'correction',
  'vocabulary',
];

class _KorlixAgentMemoryDraftSheet
    extends StatefulWidget {
  const _KorlixAgentMemoryDraftSheet({
    required this.agent,
  });

  final KorlixLiveConvoAgent agent;

  @override
  State<_KorlixAgentMemoryDraftSheet>
  createState() {
    return _KorlixAgentMemoryDraftSheetState();
  }
}

class _KorlixAgentMemoryDraftSheetState
    extends State<_KorlixAgentMemoryDraftSheet> {
  final TextEditingController _labelController =
      TextEditingController();

  final TextEditingController _contentController =
      TextEditingController();

  final TextEditingController _tagsController =
      TextEditingController();

  String _kind = 'preference';

  int _importance = 3;

  bool _sensitive = false;
  bool _confirmed = false;

  String? _validationMessage;

  @override
  void dispose() {
    _labelController.dispose();
    _contentController.dispose();
    _tagsController.dispose();

    super.dispose();
  }

  String _draftKindLabel(
    String value,
  ) {
    switch (value.trim().toLowerCase()) {
      case 'fact':
        return 'Fact';

      case 'goal':
        return 'Goal';

      case 'style':
        return 'Style';

      case 'example':
        return 'Example';

      case 'correction':
        return 'Correction';

      case 'vocabulary':
        return 'Vocabulary';

      case 'preference':
      default:
        return 'Preference';
    }
  }

  String _draftKindDescription(
    String value,
  ) {
    switch (value.trim().toLowerCase()) {
      case 'fact':
        return 'A confirmed name, detail, date, value, or other fact.';

      case 'goal':
        return 'An objective this agent should help the user achieve.';

      case 'style':
        return 'A preferred tone, layout, format, or creative direction.';

      case 'example':
        return 'An approved example this agent may use as guidance.';

      case 'correction':
        return 'A correction to something the agent previously misunderstood.';

      case 'vocabulary':
        return 'A word, phrase, translation, or language-learning record.';

      case 'preference':
      default:
        return 'A user preference this agent should apply when relevant.';
    }
  }

  IconData _draftKindIcon(
    String value,
  ) {
    switch (value.trim().toLowerCase()) {
      case 'fact':
        return Icons.fact_check_rounded;

      case 'goal':
        return Icons.flag_rounded;

      case 'style':
        return Icons.tune_rounded;

      case 'example':
        return Icons.lightbulb_rounded;

      case 'correction':
        return Icons.rule_rounded;

      case 'vocabulary':
        return Icons.translate_rounded;

      case 'preference':
      default:
        return Icons.favorite_rounded;
    }
  }

  Color _draftKindColor(
    String value,
  ) {
    switch (value.trim().toLowerCase()) {
      case 'fact':
        return const Color(0xFF69D9E8);

      case 'goal':
        return const Color(0xFFF2C14E);

      case 'style':
        return const Color(0xFFB794F4);

      case 'example':
        return const Color(0xFFFFB86B);

      case 'correction':
        return const Color(0xFFFF7185);

      case 'vocabulary':
        return const Color(0xFF7CC4FF);

      case 'preference':
      default:
        return const Color(0xFF62D6A7);
    }
  }

  List<String> _normalizedDraftTags() {
    final result = <String>[];
    final seen = <String>{};

    final candidates = _tagsController.text
        .split(
          RegExp(r'[\n,;]+'),
        )
        .map(
          (tag) => tag.trim(),
        )
        .where(
          (tag) => tag.isNotEmpty,
        );

    for (final candidate in candidates) {
      final clean = candidate.length <= 48
          ? candidate
          : candidate.substring(0, 48);

      final key = clean.toLowerCase();

      if (!seen.add(key)) {
        continue;
      }

      result.add(clean);

      if (result.length >= 12) {
        break;
      }
    }

    return List<String>.unmodifiable(
      result,
    );
  }

  void _clearDraftValidation() {
    if (_validationMessage == null) {
      return;
    }

    setState(() {
      _validationMessage = null;
    });
  }

  void _submitMemoryDraft() {
    final content =
        _contentController.text.trim();

    if (content.isEmpty) {
      setState(() {
        _validationMessage =
            'Enter the fact, preference, goal, '
            'style, example, correction, or '
            'vocabulary record to remember.';
      });

      return;
    }

    if (!_confirmed) {
      setState(() {
        _validationMessage =
            'Confirm that this record may be '
            'saved in ${widget.agent.name} '
            'private long-term memory.';
      });

      return;
    }

    Navigator.of(context).pop(
      KorlixLiveConvoMemoryDraft(
        content: content,
        confirmed: true,
        kind: _kind,
        label:
            _labelController.text.trim(),
        tags:
            _normalizedDraftTags(),
        importance:
            _importance,
        sensitive:
            _sensitive,
        source:
            'agent_hub_memory',
      ),
    );
  }

  InputDecoration _memoryDraftDecoration({
    required String label,
    String? hint,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      alignLabelWithHint: true,
      filled: true,
      fillColor:
          const Color(0xFF071722),
      labelStyle:
          const TextStyle(
        color:
            Color(0xFF8CDDE8),
        fontWeight:
            FontWeight.w800,
      ),
      hintStyle:
          const TextStyle(
        color:
            Color(0xFF718A96),
      ),
      helperStyle:
          const TextStyle(
        color:
            Color(0xFF8FA8B1),
        height: 1.3,
      ),
      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            const BorderSide(
          color:
              Color(0xFF244D5C),
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            const BorderSide(
          color:
              Color(0xFF69D9E8),
          width: 1.6,
        ),
      ),
      errorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            const BorderSide(
          color:
              Color(0xFFFF7185),
        ),
      ),
    );
  }

  Widget _buildMemoryDraftHeader(
    Color accent,
  ) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(16),
            color:
                accent.withValues(
              alpha: 0.14,
            ),
            border: Border.all(
              color:
                  accent.withValues(
                alpha: 0.72,
              ),
            ),
          ),
          child: Icon(
            Icons.add_task_rounded,
            color: accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'ADD CONFIRMED MEMORY',
                style: TextStyle(
                  color:
                      Color(0xFFF0F7F8),
                  fontSize: 19,
                  fontWeight:
                      FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Save a private record for '
                '${widget.agent.name}.',
                style: const TextStyle(
                  color:
                      Color(0xFFA9C6CF),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close memory form',
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.close_rounded,
          ),
          color:
              const Color(0xFFC7D7DC),
        ),
      ],
    );
  }

  Widget _buildMemoryKindSelector(
    Color accent,
  ) {
    final selectedColor =
        _draftKindColor(_kind);

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'MEMORY TYPE',
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind
                in _korlixAgentMemoryKindIds)
              Builder(
                builder: (context) {
                  final selected =
                      kind == _kind;

                  final kindColor =
                      _draftKindColor(kind);

                  return ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _kind = kind;
                        _validationMessage = null;
                      });
                    },
                    avatar: Icon(
                      _draftKindIcon(kind),
                      size: 18,
                      color: selected
                          ? kindColor
                          : const Color(
                              0xFF8FA8B1,
                            ),
                    ),
                    label: Text(
                      _draftKindLabel(kind),
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? const Color(
                              0xFFF0F7F8,
                            )
                          : const Color(
                              0xFFB1C4CA,
                            ),
                      fontWeight:
                          FontWeight.w800,
                    ),
                    selectedColor:
                        kindColor.withValues(
                      alpha: 0.20,
                    ),
                    backgroundColor:
                        const Color(
                      0xFF071722,
                    ),
                    side: BorderSide(
                      color: selected
                          ? kindColor
                          : const Color(
                              0xFF244D5C,
                            ),
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        999,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(15),
            color:
                selectedColor.withValues(
              alpha: 0.10,
            ),
            border: Border.all(
              color:
                  selectedColor.withValues(
                alpha: 0.46,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Icon(
                _draftKindIcon(_kind),
                color: selectedColor,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _draftKindDescription(
                    _kind,
                  ),
                  style: const TextStyle(
                    color:
                        Color(0xFFD8E7EA),
                    height: 1.4,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _importanceDescription(
    int value,
  ) {
    switch (value) {
      case 1:
        return 'Low priority. Use only when directly relevant.';

      case 2:
        return 'Useful context for occasional related requests.';

      case 4:
        return 'High priority for this agent’s related work.';

      case 5:
        return 'Critical preference or fact to apply whenever relevant.';

      case 3:
      default:
        return 'Normal priority for relevant future conversations.';
    }
  }

  Widget _buildImportanceSelector(
    Color accent,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(17),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color:
              const Color(0xFF244D5C),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color:
                    Color(0xFFF2C14E),
                size: 21,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Importance',
                  style: TextStyle(
                    color:
                        Color(0xFFF0F7F8),
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$_importance / 5',
                style: TextStyle(
                  color: accent,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (
                var level = 1;
                level <= 5;
                level += 1
              )
                ChoiceChip(
                  selected:
                      _importance == level,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() {
                      _importance = level;
                      _validationMessage = null;
                    });
                  },
                  avatar: Icon(
                    level <= _importance
                        ? Icons.star_rounded
                        : Icons
                            .star_border_rounded,
                    size: 17,
                    color:
                        const Color(
                      0xFFF2C14E,
                    ),
                  ),
                  label: Text(
                    '$level',
                  ),
                  labelStyle: const TextStyle(
                    color:
                        Color(0xFFF0F7F8),
                    fontWeight:
                        FontWeight.w900,
                  ),
                  selectedColor:
                      const Color(
                    0xFF3A3218,
                  ),
                  backgroundColor:
                      const Color(
                    0xFF0A1B24,
                  ),
                  side: BorderSide(
                    color:
                        _importance == level
                        ? const Color(
                            0xFFF2C14E,
                          )
                        : const Color(
                            0xFF244D5C,
                          ),
                  ),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _importanceDescription(
              _importance,
            ),
            style: const TextStyle(
              color:
                  Color(0xFFA9C6CF),
              height: 1.35,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensitiveMemoryControl(
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        13,
        10,
        10,
        10,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(17),
        color: _sensitive
            ? const Color(0xFF302217)
            : const Color(0xFF071722),
        border: Border.all(
          color: _sensitive
              ? const Color(
                  0xFFFFB86B,
                )
              : const Color(
                  0xFF244D5C,
                ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.only(
              top: 3,
            ),
            child: Icon(
              _sensitive
                  ? Icons
                      .privacy_tip_rounded
                  : Icons
                      .privacy_tip_outlined,
              color: _sensitive
                  ? const Color(
                      0xFFFFB86B,
                    )
                  : accent,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Sensitive memory',
                  style: TextStyle(
                    color:
                        Color(0xFFF0F7F8),
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Mark private details that '
                  'the agent should avoid '
                  'repeating unnecessarily. '
                  'This label supplements, '
                  'but does not replace, '
                  'account access controls.',
                  style: TextStyle(
                    color:
                        Color(0xFFA9C6CF),
                    height: 1.35,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: _sensitive,
            onChanged: (value) {
              setState(() {
                _sensitive = value;
                _validationMessage = null;
              });
            },
            activeThumbColor:
                const Color(
              0xFFFFB86B,
            ),
            activeTrackColor:
                const Color(
              0x665B4026,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryConsentControl(
    Color accent,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(17),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color: _confirmed
              ? accent
              : const Color(
                  0xFF244D5C,
                ),
        ),
      ),
      child: CheckboxListTile(
        value: _confirmed,
        onChanged: (value) {
          setState(() {
            _confirmed =
                value == true;

            _validationMessage =
                null;
          });
        },
        controlAffinity:
            ListTileControlAffinity.leading,
        activeColor: accent,
        checkColor:
            const Color(0xFF03110E),
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        title: Text(
          'Save in ${widget.agent.name} '
          'long-term memory',
          style: const TextStyle(
            color:
                Color(0xFFF0F7F8),
            fontWeight:
                FontWeight.w900,
          ),
        ),
        subtitle: const Text(
          'I confirm that this record may '
          'remain available to this agent '
          'across future sessions until I '
          'delete it, clear the agent’s '
          'memory, or reset the agent.',
          style: TextStyle(
            color:
                Color(0xFFA9C6CF),
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryDraftValidation() {
    final message =
        _validationMessage?.trim() ?? '';

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(14),
        color:
            const Color(0xFF351923),
        border: Border.all(
          color:
              const Color(0xFFFF7185),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color:
                Color(0xFFFF8B9B),
            size: 21,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color:
                    Color(0xFFFFD8DE),
                fontWeight:
                    FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryDraftPrivacyNotice(
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color:
            const Color(0xFF081B25),
        border: Border.all(
          color:
              accent.withValues(
            alpha: 0.48,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            color: accent,
            size: 21,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'This record is scoped to '
              '${widget.agent.name}. It is '
              'treated as lower-priority '
              'user data and cannot override '
              'Korlix safety, privacy, tool, '
              'authorization, or confirmation '
              'rules.',
              style: const TextStyle(
                color:
                    Color(0xFFA9C6CF),
                height: 1.4,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftTagChip(
    String tag,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(999),
        color:
            const Color(0xFF102B38),
        border: Border.all(
          color:
              const Color(0xFF28596A),
        ),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          color:
              Color(0xFFB7D7DE),
          fontSize: 11,
          fontWeight:
              FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDraftTagPreview() {
    return ValueListenableBuilder<
        TextEditingValue>(
      valueListenable:
          _tagsController,
      builder: (
        context,
        value,
        child,
      ) {
        final tags =
            _normalizedDraftTags();

        if (tags.isEmpty) {
          return const Text(
            'No tags added. Tags are optional.',
            style: TextStyle(
              color:
                  Color(0xFF8299A2),
              fontSize: 12,
            ),
          );
        }

        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final tag in tags)
              _buildDraftTagChip(tag),
          ],
        );
      },
    );
  }

  Widget _buildMemoryDraftFields(
    Color accent,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'MEMORY DETAILS',
          style: TextStyle(
            color: accent,
            fontWeight:
                FontWeight.w900,
            letterSpacing: 0.6,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller:
              _labelController,
          maxLength: 120,
          textInputAction:
              TextInputAction.next,
          textCapitalization:
              TextCapitalization.sentences,
          style: const TextStyle(
            color:
                Color(0xFFF0F7F8),
          ),
          decoration:
              _memoryDraftDecoration(
            label: 'Short label',
            hint:
                'Example: Report style',
            helper:
                'Optional. Use a clear name '
                'that will help you recognize '
                'this memory later.',
          ),
          onChanged: (_) {
            _clearDraftValidation();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller:
              _contentController,
          minLines: 6,
          maxLines: 14,
          maxLength: 4000,
          keyboardType:
              TextInputType.multiline,
          textInputAction:
              TextInputAction.newline,
          textCapitalization:
              TextCapitalization.sentences,
          style: const TextStyle(
            color:
                Color(0xFFF0F7F8),
            height: 1.42,
          ),
          decoration:
              _memoryDraftDecoration(
            label: 'What should this agent remember?',
            hint:
                'Example: Use a one-page '
                'executive summary for '
                'internal audit reports.',
            helper:
                'Store only information that '
                'you are authorized to retain '
                'and use in future sessions.',
          ),
          onChanged: (_) {
            _clearDraftValidation();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller:
              _tagsController,
          maxLength: 600,
          textInputAction:
              TextInputAction.done,
          style: const TextStyle(
            color:
                Color(0xFFF0F7F8),
          ),
          decoration:
              _memoryDraftDecoration(
            label: 'Tags',
            hint:
                'reports, executive, audit',
            helper:
                'Optional. Separate up to '
                '12 tags with commas, '
                'semicolons, or new lines.',
          ),
          onChanged: (_) {
            _clearDraftValidation();
          },
        ),
        const SizedBox(height: 3),
        _buildDraftTagPreview(),
      ],
    );
  }

  Widget _buildMemoryDraftActions(
    Color accent,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style:
                OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 15,
              ),
            ),
            child:
                const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed:
                _submitMemoryDraft,
            style:
                FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor:
                  const Color(0xFF03110E),
              padding:
                  const EdgeInsets.symmetric(
                vertical: 15,
              ),
            ),
            icon: const Icon(
              Icons.save_rounded,
            ),
            label: const Text(
              'Save Confirmed Memory',
              style: TextStyle(
                fontWeight:
                    FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize =
        MediaQuery.sizeOf(context);

    final bottomInset =
        MediaQuery.viewInsetsOf(
      context,
    ).bottom;

    final accent =
        korlixLiveConvoAgentAccent(
      widget.agent.accentHex,
    );

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment:
            Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight:
                screenSize.height * 0.94,
          ),
          margin:
              const EdgeInsets.only(
            top: 24,
          ),
          decoration:
              const BoxDecoration(
            color:
                Color(0xFF041019),
            borderRadius:
                BorderRadius.vertical(
              top:
                  Radius.circular(28),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color:
                    Color(0x66000000),
                blurRadius: 34,
                offset:
                    Offset(0, -8),
              ),
            ],
          ),
          clipBehavior:
              Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: ListView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior
                      .onDrag,
              padding:
                  EdgeInsets.fromLTRB(
                18,
                14,
                18,
                26 + bottomInset,
              ),
              children: [
                _buildMemoryDraftHeader(
                  accent,
                ),
                const SizedBox(height: 14),
                _buildMemoryDraftPrivacyNotice(
                  accent,
                ),
                const SizedBox(height: 18),
                _buildMemoryKindSelector(
                  accent,
                ),
                const SizedBox(height: 20),
                _buildMemoryDraftFields(
                  accent,
                ),
                const SizedBox(height: 20),
                _buildImportanceSelector(
                  accent,
                ),
                const SizedBox(height: 14),
                _buildSensitiveMemoryControl(
                  accent,
                ),
                const SizedBox(height: 14),
                _buildMemoryConsentControl(
                  accent,
                ),
                const SizedBox(height: 12),
                _buildMemoryDraftValidation(),
                const SizedBox(height: 18),
                _buildMemoryDraftActions(
                  accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> _korlixCustomAgentIconNames =
    <String>[
  'smart_toy',
  'auto_awesome',
  'support_agent',
  'description',
  'translate',
  'palette',
  'school',
  'work',
  'campaign',
  'psychology',
];

const List<String> _korlixCustomAgentAccentHexes =
    <String>[
  '21D4F4',
  '62D6A7',
  'F2C14E',
  'B794F4',
  'FF8A65',
  '7CC4FF',
  'FF7185',
  '69D9E8',
];

class _KorlixCustomAgentCreatorSheet
    extends StatefulWidget {
  const _KorlixCustomAgentCreatorSheet();

  @override
  State<_KorlixCustomAgentCreatorSheet>
  createState() {
    return _KorlixCustomAgentCreatorSheetState();
  }
}

class _KorlixCustomAgentCreatorSheetState
    extends State<_KorlixCustomAgentCreatorSheet> {
  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _descriptionController =
      TextEditingController();

  final TextEditingController _missionController =
      TextEditingController();

  final TextEditingController _trainingController =
      TextEditingController();

  final Set<String> _selectedTools =
      <String>{
    'general_chat',
    'memory',
    'agent_training',
  };

  String _iconName = 'smart_toy';
  String _accentHex = '21D4F4';

  bool _memoryEnabled = true;
  bool _confirmed = false;

  String? _validationMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _missionController.dispose();
    _trainingController.dispose();

    super.dispose();
  }

  Color get _customAccent {
    return korlixLiveConvoAgentAccent(
      _accentHex,
    );
  }

  bool _isRequiredCustomTool(
    String toolId,
  ) {
    if (toolId == 'general_chat' ||
        toolId == 'agent_training') {
      return true;
    }

    return toolId == 'memory' &&
        _memoryEnabled;
  }

  void _toggleCustomTool(
    String toolId,
    bool selected,
  ) {
    if (toolId == 'memory') {
      _toggleCustomMemory(
        selected,
      );

      return;
    }

    if (!selected &&
        _isRequiredCustomTool(
          toolId,
        )) {
      return;
    }

    setState(() {
      if (selected) {
        _selectedTools.add(
          toolId,
        );
      } else {
        _selectedTools.remove(
          toolId,
        );
      }

      _validationMessage = null;
    });
  }

  void _toggleCustomMemory(
    bool enabled,
  ) {
    setState(() {
      _memoryEnabled = enabled;

      if (enabled) {
        _selectedTools.add(
          'memory',
        );
      } else {
        _selectedTools.remove(
          'memory',
        );
      }

      _validationMessage = null;
    });
  }

  List<String> _orderedCustomTools() {
    final selected =
        Set<String>.from(
      _selectedTools,
    )
          ..add(
            'general_chat',
          )
          ..add(
            'agent_training',
          );

    if (_memoryEnabled) {
      selected.add(
        'memory',
      );
    } else {
      selected.remove(
        'memory',
      );
    }

    return List<String>.unmodifiable(
      _korlixAgentAllToolIds.where(
        selected.contains,
      ),
    );
  }

  void _clearCustomValidation() {
    if (_validationMessage == null) {
      return;
    }

    setState(() {
      _validationMessage = null;
    });
  }

  void _submitCustomAgent() {
    final name =
        _nameController.text.trim();

    final description =
        _descriptionController.text.trim();

    final mission =
        _missionController.text.trim();

    final training =
        _trainingController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _validationMessage =
            'Enter a name for the custom agent.';
      });

      return;
    }

    if (mission.isEmpty) {
      setState(() {
        _validationMessage =
            'Describe the custom agent mission '
            'and the work it should perform.';
      });

      return;
    }

    if (!_confirmed) {
      setState(() {
        _validationMessage =
            'Confirm that this custom agent, '
            'its instructions, and its enabled '
            'tools may be saved to your account.';
      });

      return;
    }

    Navigator.of(context).pop(
      KorlixLiveConvoCustomAgentDraft(
        name: name,

        description:
            description.isEmpty
            ? 'A private, trainable '
                'LIVE CONVO agent.'
            : description,

        mission: mission,

        iconName:
            _iconName,

        accentHex:
            _accentHex,

        trainingInstructions:
            training,

        toolIds:
            _orderedCustomTools(),

        memoryEnabled:
            _memoryEnabled,
      ),
    );
  }

  InputDecoration _customAgentDecoration({
    required String label,
    String? hint,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      alignLabelWithHint: true,
      filled: true,
      fillColor:
          const Color(0xFF071722),
      labelStyle:
          const TextStyle(
        color:
            Color(0xFF8CDDE8),
        fontWeight:
            FontWeight.w800,
      ),
      hintStyle:
          const TextStyle(
        color:
            Color(0xFF718A96),
      ),
      helperStyle:
          const TextStyle(
        color:
            Color(0xFF8FA8B1),
        height: 1.3,
      ),
      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            const BorderSide(
          color:
              Color(0xFF244D5C),
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            BorderSide(
          color:
              _customAccent,
          width: 1.6,
        ),
      ),
      errorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(16),
        borderSide:
            const BorderSide(
          color:
              Color(0xFFFF7185),
        ),
      ),
    );
  }

  Widget _buildCustomAgentHeader() {
    final accent =
        _customAccent;

    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(16),
            color:
                accent.withValues(
              alpha: 0.14,
            ),
            border: Border.all(
              color:
                  accent.withValues(
                alpha: 0.72,
              ),
            ),
          ),
          child: Icon(
            korlixLiveConvoAgentIcon(
              _iconName,
            ),
            color: accent,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'CREATE YOUR OWN AGENT',
                style: TextStyle(
                  color:
                      Color(0xFFF0F7F8),
                  fontSize: 19,
                  fontWeight:
                      FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Build a private specialist '
                'with its own mission, training, '
                'tools, and long-term memory.',
                style: TextStyle(
                  color:
                      Color(0xFFA9C6CF),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip:
              'Close custom-agent creator',
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.close_rounded,
          ),
          color:
              const Color(0xFFC7D7DC),
        ),
      ],
    );
  }

  Widget _buildCustomAgentPrivacyNotice() {
    final accent =
        _customAccent;

    return Container(
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color:
            const Color(0xFF081B25),
        border: Border.all(
          color:
              accent.withValues(
            alpha: 0.48,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: accent,
            size: 21,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Custom training and memories '
              'are lower-priority user data. '
              'They cannot override Korlix '
              'safety, privacy, authorization, '
              'tool, credit, or confirmation '
              'rules.',
              style: TextStyle(
                color:
                    Color(0xFFA9C6CF),
                height: 1.4,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _customIconLabel(
    String iconName,
  ) {
    switch (iconName) {
      case 'auto_awesome':
        return 'Creative';

      case 'support_agent':
        return 'Assistant';

      case 'description':
        return 'Documents';

      case 'translate':
        return 'Language';

      case 'palette':
        return 'Design';

      case 'school':
        return 'Teacher';

      case 'work':
        return 'Business';

      case 'campaign':
        return 'Marketing';

      case 'psychology':
        return 'Coach';

      case 'smart_toy':
      default:
        return 'Agent';
    }
  }

  String _customAccentLabel(
    String accentHex,
  ) {
    switch (accentHex) {
      case '62D6A7':
        return 'Emerald';

      case 'F2C14E':
        return 'Gold';

      case 'B794F4':
        return 'Violet';

      case 'FF8A65':
        return 'Coral';

      case '7CC4FF':
        return 'Sky';

      case 'FF7185':
        return 'Rose';

      case '69D9E8':
        return 'Aqua';

      case '21D4F4':
      default:
        return 'Korlix Blue';
    }
  }

  Widget _buildCustomIdentityFields() {
    final accent =
        _customAccent;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'AGENT IDENTITY',
          style: TextStyle(
            color: accent,
            fontWeight:
                FontWeight.w900,
            letterSpacing: 0.6,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller:
              _nameController,
          maxLength: 80,
          textInputAction:
              TextInputAction.next,
          textCapitalization:
              TextCapitalization.words,
          style: const TextStyle(
            color:
                Color(0xFFF0F7F8),
          ),
          decoration:
              _customAgentDecoration(
            label: 'Agent name',
            hint:
                'Example: Brand Coach',
            helper:
                'Use a short, clear name '
                'that describes the specialist.',
          ),
          onChanged: (_) {
            _clearCustomValidation();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller:
              _descriptionController,
          maxLength: 240,
          minLines: 2,
          maxLines: 4,
          textInputAction:
              TextInputAction.next,
          textCapitalization:
              TextCapitalization.sentences,
          style: const TextStyle(
            color:
                Color(0xFFF0F7F8),
            height: 1.4,
          ),
          decoration:
              _customAgentDecoration(
            label: 'Short description',
            hint:
                'Example: Private guidance '
                'for brand voice and campaigns.',
            helper:
                'This appears in the '
                'LIVE CONVO Agent Hub.',
          ),
          onChanged: (_) {
            _clearCustomValidation();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller:
              _missionController,
          maxLength: 2400,
          minLines: 5,
          maxLines: 10,
          keyboardType:
              TextInputType.multiline,
          textInputAction:
              TextInputAction.newline,
          textCapitalization:
              TextCapitalization.sentences,
          style: const TextStyle(
            color:
                Color(0xFFF0F7F8),
            height: 1.42,
          ),
          decoration:
              _customAgentDecoration(
            label: 'Mission',
            hint:
                'Describe the work this '
                'agent should perform, the '
                'users it should help, and '
                'the results it should produce.',
            helper:
                'The mission is required. '
                'It remains subject to all '
                'protected Korlix rules.',
          ),
          onChanged: (_) {
            _clearCustomValidation();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller:
              _trainingController,
          maxLength: 12000,
          minLines: 4,
          maxLines: 10,
          keyboardType:
              TextInputType.multiline,
          textInputAction:
              TextInputAction.newline,
          textCapitalization:
              TextCapitalization.sentences,
          style: const TextStyle(
            color:
                Color(0xFFF0F7F8),
            height: 1.42,
          ),
          decoration:
              _customAgentDecoration(
            label:
                'Initial training instructions',
            hint:
                'Example: Use concise '
                'recommendations, follow the '
                'approved brand vocabulary, '
                'and end with next actions.',
            helper:
                'Optional. You can add or '
                'replace training later.',
          ),
          onChanged: (_) {
            _clearCustomValidation();
          },
        ),
      ],
    );
  }

  Widget _buildCustomIconSelector() {
    final accent =
        _customAccent;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'AGENT ICON',
          style: TextStyle(
            color: accent,
            fontWeight:
                FontWeight.w900,
            letterSpacing: 0.6,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final iconName
                in _korlixCustomAgentIconNames)
              Builder(
                builder: (context) {
                  final selected =
                      iconName ==
                      _iconName;

                  return ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _iconName =
                            iconName;

                        _validationMessage =
                            null;
                      });
                    },
                    avatar: Icon(
                      korlixLiveConvoAgentIcon(
                        iconName,
                      ),
                      size: 19,
                      color: selected
                          ? accent
                          : const Color(
                              0xFF8FA8B1,
                            ),
                    ),
                    label: Text(
                      _customIconLabel(
                        iconName,
                      ),
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? const Color(
                              0xFFF0F7F8,
                            )
                          : const Color(
                              0xFFB1C4CA,
                            ),
                      fontWeight:
                          FontWeight.w800,
                    ),
                    selectedColor:
                        accent.withValues(
                      alpha: 0.18,
                    ),
                    backgroundColor:
                        const Color(
                      0xFF071722,
                    ),
                    side: BorderSide(
                      color: selected
                          ? accent
                          : const Color(
                              0xFF244D5C,
                            ),
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        999,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomAccentSelector() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'ACCENT COLOR',
          style: TextStyle(
            color:
                _customAccent,
            fontWeight:
                FontWeight.w900,
            letterSpacing: 0.6,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final accentHex
                in _korlixCustomAgentAccentHexes)
              Builder(
                builder: (context) {
                  final selected =
                      accentHex ==
                      _accentHex;

                  final color =
                      korlixLiveConvoAgentAccent(
                    accentHex,
                  );

                  return Material(
                    color:
                        Colors.transparent,
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(
                        16,
                      ),
                      onTap: () {
                        setState(() {
                          _accentHex =
                              accentHex;

                          _validationMessage =
                              null;
                        });
                      },
                      child: AnimatedContainer(
                        duration:
                            const Duration(
                          milliseconds: 160,
                        ),
                        width: 94,
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 9,
                          vertical: 9,
                        ),
                        decoration:
                            BoxDecoration(
                          borderRadius:
                              BorderRadius
                                  .circular(16),
                          color:
                              selected
                              ? color.withValues(
                                  alpha: 0.16,
                                )
                              : const Color(
                                  0xFF071722,
                                ),
                          border:
                              Border.all(
                            color:
                                selected
                                ? color
                                : const Color(
                                    0xFF244D5C,
                                  ),
                            width:
                                selected
                                ? 1.6
                                : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration:
                                  BoxDecoration(
                                shape:
                                    BoxShape.circle,
                                color: color,
                                boxShadow:
                                    <BoxShadow>[
                                  BoxShadow(
                                    color:
                                        color.withValues(
                                      alpha: 0.24,
                                    ),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: selected
                                  ? const Icon(
                                      Icons
                                          .check_rounded,
                                      color:
                                          Color(
                                        0xFF03110E,
                                      ),
                                      size: 21,
                                    )
                                  : null,
                            ),
                            const SizedBox(
                              height: 7,
                            ),
                            Text(
                              _customAccentLabel(
                                accentHex,
                              ),
                              textAlign:
                                  TextAlign.center,
                              style:
                                  TextStyle(
                                color:
                                    selected
                                    ? color
                                    : const Color(
                                        0xFFA9C6CF,
                                      ),
                                fontSize: 11,
                                fontWeight:
                                    FontWeight
                                        .w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomMemoryControl() {
    final accent =
        _customAccent;

    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        13,
        10,
        10,
        10,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(17),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color: _memoryEnabled
              ? accent.withValues(
                  alpha: 0.72,
                )
              : const Color(
                  0xFF244D5C,
                ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.only(
              top: 3,
            ),
            child: Icon(
              _memoryEnabled
                  ? Icons
                      .psychology_alt_rounded
                  : Icons
                      .memory_outlined,
              color: _memoryEnabled
                  ? accent
                  : const Color(
                      0xFF8299A2,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Private long-term memory',
                  style: TextStyle(
                    color:
                        Color(0xFFF0F7F8),
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Allows this custom agent '
                  'to load and save only its '
                  'own user-confirmed memories '
                  'across future sessions.',
                  style: TextStyle(
                    color:
                        Color(0xFFA9C6CF),
                    height: 1.35,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value:
                _memoryEnabled,
            onChanged:
                _toggleCustomMemory,
            activeThumbColor:
                accent,
            activeTrackColor:
                accent.withValues(
              alpha: 0.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomToolPermissions() {
    final accent =
        _customAccent;

    final tools =
        _korlixAgentAllToolIds
            .where(
              (toolId) =>
                  toolId != 'memory',
            )
            .toList(
              growable: false,
            );

    final enabledToolCount =
        _orderedCustomTools().length;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'AUTHORIZED TOOLS',
          style: TextStyle(
            color: accent,
            fontWeight:
                FontWeight.w900,
            letterSpacing: 0.6,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '$enabledToolCount tools are enabled. '
          'General conversation and agent '
          'training are required.',
          style: const TextStyle(
            color:
                Color(0xFFA9C6CF),
            height: 1.35,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 9),
        Container(
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(18),
            color:
                const Color(0xFF071722),
            border: Border.all(
              color:
                  const Color(0xFF244D5C),
            ),
          ),
          clipBehavior:
              Clip.antiAlias,
          child: Column(
            children: [
              for (
                var index = 0;
                index < tools.length;
                index += 1
              ) ...[
                Builder(
                  builder: (context) {
                    final toolId =
                        tools[index];

                    final required =
                        _isRequiredCustomTool(
                      toolId,
                    );

                    final selected =
                        _selectedTools.contains(
                      toolId,
                    );

                    return CheckboxListTile(
                      value: selected,
                      onChanged: required
                          ? (_) {}
                          : (value) {
                              if (value ==
                                  null) {
                                return;
                              }

                              _toggleCustomTool(
                                toolId,
                                value,
                              );
                            },
                      controlAffinity:
                          ListTileControlAffinity
                              .leading,
                      activeColor: accent,
                      checkColor:
                          const Color(
                        0xFF03110E,
                      ),
                      contentPadding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _korlixAgentToolLabel(
                                toolId,
                              ),
                              style:
                                  TextStyle(
                                color: selected
                                    ? const Color(
                                        0xFFF0F7F8,
                                      )
                                    : const Color(
                                        0xFF8299A2,
                                      ),
                                fontWeight:
                                    FontWeight
                                        .w800,
                              ),
                            ),
                          ),
                          if (required)
                            _KorlixAgentBadge(
                              text: 'REQUIRED',
                              color: accent,
                            ),
                        ],
                      ),
                      subtitle: Text(
                        _korlixAgentToolDescription(
                          toolId,
                        ),
                        style:
                            const TextStyle(
                          color:
                              Color(
                            0xFFA9C6CF,
                          ),
                          height: 1.3,
                          fontSize: 12.5,
                        ),
                      ),
                    );
                  },
                ),
                if (index !=
                    tools.length - 1)
                  const Divider(
                    height: 1,
                    color:
                        Color(
                      0xFF173541,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 9),
        Container(
          padding:
              const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(15),
            color:
                const Color(0xFF081B25),
            border: Border.all(
              color:
                  accent.withValues(
                alpha: 0.42,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                color: accent,
                size: 21,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Selecting a tool only gives '
                  'the agent permission to '
                  'request that capability. '
                  'Normal authentication, credit, '
                  'confirmation, file, camera, '
                  'and safety checks still apply.',
                  style: TextStyle(
                    color:
                        Color(
                      0xFFA9C6CF,
                    ),
                    height: 1.4,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomConsentControl() {
    final accent =
        _customAccent;

    return Container(
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(17),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color: _confirmed
              ? accent
              : const Color(
                  0xFF244D5C,
                ),
        ),
      ),
      child: CheckboxListTile(
        value: _confirmed,
        onChanged: (value) {
          setState(() {
            _confirmed =
                value == true;

            _validationMessage =
                null;
          });
        },
        controlAffinity:
            ListTileControlAffinity
                .leading,
        activeColor: accent,
        checkColor:
            const Color(0xFF03110E),
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        title: const Text(
          'Create and save this custom agent',
          style: TextStyle(
            color:
                Color(0xFFF0F7F8),
            fontWeight:
                FontWeight.w900,
          ),
        ),
        subtitle: const Text(
          'I confirm that this mission, '
          'training, appearance, enabled '
          'tools, and memory setting may '
          'remain saved to my account until '
          'I update or delete the agent.',
          style: TextStyle(
            color:
                Color(0xFFA9C6CF),
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomValidation() {
    final message =
        _validationMessage?.trim() ?? '';

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(14),
        color:
            const Color(0xFF351923),
        border: Border.all(
          color:
              const Color(0xFFFF7185),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color:
                Color(0xFFFF8B9B),
            size: 21,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color:
                    Color(0xFFFFD8DE),
                fontWeight:
                    FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomAgentActions() {
    final accent =
        _customAccent;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style:
                OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 15,
              ),
            ),
            child:
                const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed:
                _submitCustomAgent,
            style:
                FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor:
                  const Color(0xFF03110E),
              padding:
                  const EdgeInsets.symmetric(
                vertical: 15,
              ),
            ),
            icon: const Icon(
              Icons.add_circle_rounded,
            ),
            label: const Text(
              'Create Agent',
              style: TextStyle(
                fontWeight:
                    FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize =
        MediaQuery.sizeOf(context);

    final bottomInset =
        MediaQuery.viewInsetsOf(
      context,
    ).bottom;

    final accent =
        _customAccent;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment:
            Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 820,
            maxHeight:
                screenSize.height * 0.94,
          ),
          margin:
              const EdgeInsets.only(
            top: 24,
          ),
          decoration:
              const BoxDecoration(
            color:
                Color(0xFF041019),
            borderRadius:
                BorderRadius.vertical(
              top:
                  Radius.circular(28),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color:
                    Color(0x66000000),
                blurRadius: 34,
                offset:
                    Offset(0, -8),
              ),
            ],
          ),
          clipBehavior:
              Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: ListView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior
                      .onDrag,
              padding:
                  EdgeInsets.fromLTRB(
                18,
                14,
                18,
                26 + bottomInset,
              ),
              children: [
                _buildCustomAgentHeader(),
                const SizedBox(height: 14),
                _buildCustomAgentPrivacyNotice(),
                const SizedBox(height: 20),
                _buildCustomIdentityFields(),
                const SizedBox(height: 20),
                _buildCustomIconSelector(),
                const SizedBox(height: 20),
                _buildCustomAccentSelector(),
                const SizedBox(height: 20),
                Text(
                  'MEMORY',
                  style: TextStyle(
                    color: accent,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.6,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                _buildCustomMemoryControl(),
                const SizedBox(height: 20),
                _buildCustomToolPermissions(),
                const SizedBox(height: 18),
                _buildCustomConsentControl(),
                const SizedBox(height: 12),
                _buildCustomValidation(),
                const SizedBox(height: 18),
                _buildCustomAgentActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KorlixAgentVersionHistorySheet
    extends StatelessWidget {
  const _KorlixAgentVersionHistorySheet({
    required this.agent,
    required this.versions,
  });

  final KorlixLiveConvoAgent agent;
  final List<KorlixLiveConvoAgentVersion> versions;

  Object? _snapshotValue(
    KorlixLiveConvoAgentVersion version,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (version.snapshot.containsKey(key)) {
        return version.snapshot[key];
      }
    }

    return null;
  }

  String _snapshotText(
    KorlixLiveConvoAgentVersion version,
    List<String> keys, {
    String fallback = '',
  }) {
    final value =
        _snapshotValue(
      version,
      keys,
    );

    final text =
        (value ?? '').toString().trim();

    return text.isEmpty
        ? fallback
        : text;
  }

  bool _snapshotBool(
    KorlixLiveConvoAgentVersion version,
    List<String> keys, {
    required bool fallback,
  }) {
    final value =
        _snapshotValue(
      version,
      keys,
    );

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized =
        (value ?? '')
            .toString()
            .trim()
            .toLowerCase();

    if (<String>{
      'true',
      'yes',
      'on',
      '1',
    }.contains(normalized)) {
      return true;
    }

    if (<String>{
      'false',
      'no',
      'off',
      '0',
    }.contains(normalized)) {
      return false;
    }

    return fallback;
  }

  List<String> _snapshotTools(
    KorlixLiveConvoAgentVersion version,
  ) {
    final raw =
        _snapshotValue(
      version,
      const <String>[
        'toolIds',
        'tool_ids',
        'tools',
      ],
    );

    if (raw is! Iterable<Object?>) {
      return agent.toolIds;
    }

    final result = <String>[];
    final seen = <String>{};

    for (final item in raw) {
      final toolId =
          (item ?? '')
              .toString()
              .trim();

      if (toolId.isEmpty ||
          !seen.add(toolId)) {
        continue;
      }

      result.add(toolId);
    }

    return result.isEmpty
        ? agent.toolIds
        : List<String>.unmodifiable(
            result,
          );
  }

  String _versionDate(
    DateTime? value,
  ) {
    if (value == null) {
      return 'Date unavailable';
    }

    final local =
        value.toLocal();

    final hour =
        local.hour % 12 == 0
        ? 12
        : local.hour % 12;

    final minute =
        local.minute
            .toString()
            .padLeft(2, '0');

    final period =
        local.hour >= 12
        ? 'PM'
        : 'AM';

    return '${local.month}/${local.day}/${local.year} '
        '$hour:$minute $period';
  }

  String _versionSourceLabel(
    String source,
  ) {
    final clean =
        source
            .trim()
            .replaceAll('_', ' ');

    if (clean.isEmpty) {
      return 'Training update';
    }

    return clean
        .split(' ')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
          (word) =>
              '${word[0].toUpperCase()}'
              '${word.substring(1)}',
        )
        .join(' ');
  }

  Widget _buildVersionToolChip(
    String toolId,
    Color accent,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(999),
        color:
            accent.withValues(
          alpha: 0.10,
        ),
        border: Border.all(
          color:
              accent.withValues(
            alpha: 0.38,
          ),
        ),
      ),
      child: Text(
        _korlixAgentToolLabel(
          toolId,
        ),
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight:
              FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildVersionCard(
    BuildContext context,
    KorlixLiveConvoAgentVersion version,
    Color accent,
  ) {
    final isCurrent =
        version.version ==
        agent.version;

    final training =
        _snapshotText(
      version,
      const <String>[
        'trainingInstructions',
        'training_instructions',
      ],
    );

    final mission =
        _snapshotText(
      version,
      const <String>[
        'mission',
      ],
      fallback: agent.mission,
    );

    final tools =
        _snapshotTools(
      version,
    );

    final memoryEnabled =
        _snapshotBool(
      version,
      const <String>[
        'memoryEnabled',
        'memory_enabled',
      ],
      fallback:
          agent.memoryEnabled,
    );

    final sourceLabel =
        _versionSourceLabel(
      version.source,
    );

    final dateLabel =
        _versionDate(
      version.createdAt,
    );

    return Container(
      margin:
          const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding:
          const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(20),
        color: isCurrent
            ? accent.withValues(
                alpha: 0.12,
              )
            : const Color(
                0xFF071722,
              ),
        border: Border.all(
          color: isCurrent
              ? accent
              : const Color(
                  0xFF244D5C,
                ),
          width:
              isCurrent ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                  color:
                      accent.withValues(
                    alpha: 0.14,
                  ),
                  border: Border.all(
                    color:
                        accent.withValues(
                      alpha: 0.58,
                    ),
                  ),
                ),
                child: Icon(
                  isCurrent
                      ? Icons
                          .verified_rounded
                      : Icons
                          .history_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment:
                          WrapCrossAlignment
                              .center,
                      children: [
                        Text(
                          'Version '
                          '${version.version}',
                          style:
                              const TextStyle(
                            color:
                                Color(
                              0xFFF0F7F8,
                            ),
                            fontSize: 16,
                            fontWeight:
                                FontWeight
                                    .w900,
                          ),
                        ),
                        if (isCurrent)
                          _KorlixAgentBadge(
                            text: 'CURRENT',
                            color: accent,
                          )
                        else
                          const _KorlixAgentBadge(
                            text: 'RESTORABLE',
                            color:
                                Color(
                              0xFFB794F4,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$sourceLabel · '
                      '$dateLabel',
                      style:
                          const TextStyle(
                        color:
                            Color(
                          0xFF8FA8B1,
                        ),
                        height: 1.3,
                        fontSize: 12,
                        fontWeight:
                            FontWeight
                                .w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Text(
            'TRAINING',
            style: TextStyle(
              color:
                  Color(0xFF8CDDE8),
              fontSize: 11.5,
              fontWeight:
                  FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            training.isEmpty
                ? 'No personal training '
                    'was saved in this version.'
                : training,
            maxLines: 7,
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              color: training.isEmpty
                  ? const Color(
                      0xFF8299A2,
                    )
                  : const Color(
                      0xFFD8E7EA,
                    ),
              height: 1.42,
              fontStyle: training.isEmpty
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'MISSION',
            style: TextStyle(
              color:
                  Color(0xFF8CDDE8),
              fontSize: 11.5,
              fontWeight:
                  FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            mission,
            maxLines: 4,
            overflow:
                TextOverflow.ellipsis,
            style: const TextStyle(
              color:
                  Color(0xFFBBD0D6),
              height: 1.4,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final toolId in tools)
                _buildVersionToolChip(
                  toolId,
                  accent,
                ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                memoryEnabled
                    ? Icons
                        .psychology_alt_rounded
                    : Icons
                        .memory_outlined,
                size: 19,
                color: memoryEnabled
                    ? const Color(
                        0xFF62D6A7,
                      )
                    : const Color(
                        0xFF8299A2,
                      ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  memoryEnabled
                      ? 'Long-term memory enabled'
                      : 'Long-term memory disabled',
                  style: TextStyle(
                    color: memoryEnabled
                        ? const Color(
                            0xFF62D6A7,
                          )
                        : const Color(
                            0xFF8299A2,
                          ),
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
              if (!isCurrent)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(
                      version.version,
                    );
                  },
                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(
                      color: accent,
                    ),
                  ),
                  icon: const Icon(
                    Icons.restore_rounded,
                  ),
                  label: const Text(
                    'Select',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVersionHistoryHeader(
    BuildContext context,
    Color accent,
  ) {
    final count = versions.length;

    final countLabel = count == 1
        ? '1 saved training version'
        : '$count saved training versions';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        12,
        12,
        10,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(16),
              color: accent.withValues(
                alpha: 0.14,
              ),
              border: Border.all(
                color: accent.withValues(
                  alpha: 0.72,
                ),
              ),
            ),
            child: Icon(
              Icons.history_rounded,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '${agent.name.toUpperCase()} HISTORY',
                  style: const TextStyle(
                    color:
                        Color(0xFFF0F7F8),
                    fontSize: 19,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  countLabel,
                  style: const TextStyle(
                    color:
                        Color(0xFFA9C6CF),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip:
                'Close training history',
            onPressed: () {
              Navigator.of(context).pop();
            },
            icon: const Icon(
              Icons.close_rounded,
            ),
            color:
                const Color(0xFFC7D7DC),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionHistoryNotice(
    Color accent,
  ) {
    final restorableCount =
        versions.where(
      (version) =>
          version.version !=
          agent.version,
    ).length;

    final message = restorableCount == 0
        ? 'The current version is the only '
            'saved training version for '
            '${agent.name}.'
        : restorableCount == 1
            ? 'One earlier training version '
                'can be restored. Selecting it '
                'will return you to a final '
                'confirmation before anything '
                'changes.'
            : '$restorableCount earlier training '
                'versions can be restored. '
                'Selecting one will return you '
                'to a final confirmation before '
                'anything changes.';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(16),
        color:
            const Color(0xFF081B25),
        border: Border.all(
          color: accent.withValues(
            alpha: 0.48,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            restorableCount == 0
                ? Icons
                    .verified_rounded
                : Icons
                    .restore_rounded,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color:
                    Color(0xFFD8E7EA),
                height: 1.4,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyVersionHistory(
    Color accent,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(20),
        color:
            const Color(0xFF071722),
        border: Border.all(
          color: accent.withValues(
            alpha: 0.46,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(
                alpha: 0.13,
              ),
              border: Border.all(
                color: accent.withValues(
                  alpha: 0.62,
                ),
              ),
            ),
            child: Icon(
              Icons.history_toggle_off_rounded,
              color: accent,
              size: 29,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'No training history yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  Color(0xFFF0F7F8),
              fontSize: 16,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Publish confirmed training for '
            '${agent.name} to create its first '
            'restorable version.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color:
                  Color(0xFFA9C6CF),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionHistoryFooter(
    BuildContext context,
    Color accent,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        2,
        16,
        18,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(16),
              color:
                  const Color(0xFF081B25),
              border: Border.all(
                color:
                    const Color(0xFF244D5C),
              ),
            ),
            child: const Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons
                      .verified_user_outlined,
                  color:
                      Color(0xFF8CDDE8),
                  size: 21,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Restoring a snapshot '
                    'publishes it as a new '
                    'active training version. '
                    'Earlier versions remain '
                    'available. Private memory '
                    'records are managed '
                    'separately from the '
                    'Memory screen.',
                    style: TextStyle(
                      color:
                          Color(0xFFA9C6CF),
                      height: 1.4,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style:
                OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(
                color: accent,
              ),
              padding:
                  const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
            ),
            icon: const Icon(
              Icons.check_rounded,
            ),
            label: const Text(
              'Keep Current Version',
              style: TextStyle(
                fontWeight:
                    FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize =
        MediaQuery.sizeOf(context);

    final accent =
        korlixLiveConvoAgentAccent(
      agent.accentHex,
    );

    final orderedVersions =
        versions.toList()
          ..sort(
            (left, right) =>
                right.version.compareTo(
              left.version,
            ),
          );

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment:
            Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 840,
            maxHeight:
                screenSize.height * 0.94,
          ),
          margin: const EdgeInsets.only(
            top: 24,
          ),
          decoration:
              const BoxDecoration(
            color:
                Color(0xFF041019),
            borderRadius:
                BorderRadius.vertical(
              top:
                  Radius.circular(28),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color:
                    Color(0x66000000),
                blurRadius: 34,
                offset:
                    Offset(0, -8),
              ),
            ],
          ),
          clipBehavior:
              Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildVersionHistoryHeader(
                  context,
                  accent,
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior
                            .onDrag,
                    padding:
                        const EdgeInsets.only(
                      bottom: 8,
                    ),
                    children: [
                      _buildVersionHistoryNotice(
                        accent,
                      ),
                      if (orderedVersions.isEmpty)
                        _buildEmptyVersionHistory(
                          accent,
                        )
                      else
                        for (
                          final version
                              in orderedVersions
                        )
                          _buildVersionCard(
                            context,
                            version,
                            accent,
                          ),
                      _buildVersionHistoryFooter(
                        context,
                        accent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// KORLIX_LIVE_CONVO_AGENT_SHEET_BUILD131_END
