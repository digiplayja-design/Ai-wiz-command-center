import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../../theme/korlix_theme.dart';
import '../../theme/korlix_action_button.dart';
import '../social_client.dart';
import '../social_design.dart';
import 'domino_controller.dart';
import 'domino_tiles.dart';

class DominoLobby extends StatefulWidget {
  const DominoLobby({super.key, required this.client, required this.profile});
  final SocialClient client;
  final SocialMap profile;
  @override
  State<DominoLobby> createState() => _DominoLobbyState();
}

class _DominoLobbyState extends State<DominoLobby> {
  List<SocialMap> tables = [];
  String? error;
  bool busy = false, loading = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_session);
    unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(load());
      }
    });
  }

  void _session() {
    if (!widget.client.available && mounted) {
      setState(() {
        tables = [];
        error = 'Sign in again to play.';
      });
    }
  }

  Future<void> load() async {
    if (loading || !widget.client.available) return;
    loading = true;
    try {
      final r = await widget.client.post('domino', {'action': 'list'});
      if (mounted && widget.client.available) {
        setState(() {
          tables = socialItems(r['items']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      loading = false;
    }
  }

  Future<void> open(SocialMap value) async {
    if (!mounted || !widget.client.available) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DominoTableScreen(client: widget.client, initial: value),
      ),
    );
    if (mounted) await load();
  }

  Future<void> create() async {
    final name = TextEditingController(text: 'Domino night');
    int seats = 4;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Create a private table'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Table name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: seats,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Players'),
                items: const [
                  DropdownMenuItem(
                    value: 2,
                    child: Text('2 players · head-to-head'),
                  ),
                  DropdownMenuItem(
                    value: 4,
                    child: Text('4 players · partner teams'),
                  ),
                ],
                onChanged: (v) => set(() => seats = v!),
              ),
              const SizedBox(height: 14),
              const Text(
                'Block dominoes. Seven tiles each. Free play. Invite accepted Social connections.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create table'),
            ),
          ],
        ),
      ),
    );
    final title = name.text.trim();
    name.dispose();
    if (choice != true || !mounted) return;
    if (title.isEmpty) {
      setState(() => error = 'Give your table a name.');
      return;
    }
    setState(() => busy = true);
    try {
      final r = await widget.client.post('domino', {
        'action': 'create',
        'id': socialId(),
        'name': title,
        'capacity': seats,
      });
      await open(socialMap(r['table']));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> join(SocialMap item) async {
    setState(() => busy = true);
    try {
      final r = await widget.client.post('domino', {
        'action': 'join',
        'id': item['id'],
      });
      await open(socialMap(r['table']));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.client.removeListener(_session);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Scaffold(
      backgroundColor: skin.backgroundBottom,
      appBar: AppBar(
        title: const Text('KORLIX Dominoes'),
        actions: [
          IconButton(
            tooltip: 'Refresh tables',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SocialPanel(
                  accent: const Color(0xFF65E7C6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KORLIX SOCIAL  /  PLAY TOGETHER',
                        style: TextStyle(
                          color: skin.secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Pull up a chair.',
                        style: TextStyle(
                          fontSize: 34,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Real friends. Live faces. One good game of dominoes.',
                        style: TextStyle(
                          color: skin.mutedText,
                          height: 1.5,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const DominoBoard(tiles: []),
                      const SizedBox(height: 20),
                      KorlixActionButton(
                        key: const Key('domino-create'),
                        label: 'Create a table',
                        icon: Icons.add_rounded,
                        onPressed: busy || !widget.client.available
                            ? null
                            : create,
                        expand: true,
                        accent: skin.secondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '2 or 4 players · Live video & audio · Always free play',
                        style: TextStyle(
                          color: skin.mutedText,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Your tables & invitations',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(error!, style: TextStyle(color: skin.danger)),
                  ),
                if (tables.isEmpty)
                  SocialPanel(
                    child: Text(
                      'Create a table and invite your connections. Invitations from friends appear here.',
                      style: TextStyle(color: skin.mutedText, height: 1.6),
                    ),
                  ),
                for (final table in tables)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SocialPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${table['name']}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hosted by ${socialMap(table['host'])['name']} · ${table['seated']}/${table['capacity']} seats',
                            style: TextStyle(color: skin.mutedText),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              KorlixActionButton(
                                label: table['status'] == 'invited'
                                    ? 'Join table'
                                    : 'Return to table',
                                icon: Icons.arrow_forward_rounded,
                                onPressed: busy ? null : () => join(table),
                                size: KorlixButtonSize.compact,
                              ),
                              if (table['status'] == 'invited')
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          try {
                                            await widget.client.post('domino', {
                                              'action': 'decline',
                                              'id': table['id'],
                                            });
                                            await load();
                                          } catch (e) {
                                            if (mounted) {
                                              setState(() => error = '$e');
                                            }
                                          }
                                        },
                                  child: const Text('Decline'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Camera and microphone start only when you choose Join video. Table sessions last up to four hours.',
                  style: TextStyle(
                    color: skin.mutedText,
                    fontSize: 12,
                    height: 1.6,
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

class DominoTableScreen extends StatefulWidget {
  const DominoTableScreen({
    super.key,
    required this.client,
    required this.initial,
    this.controller,
  });
  final SocialClient client;
  final SocialMap initial;
  final DominoController? controller;
  @override
  State<DominoTableScreen> createState() => _DominoTableScreenState();
}

class _DominoTableScreenState extends State<DominoTableScreen>
    with WidgetsBindingObserver {
  late final c =
      widget.controller ??
      DominoController(client: widget.client, initial: widget.initial);
  String? tile;
  bool leaving = false, pop = false, inviting = false;
  KorlixSkinPalette get skin => korlixSkinOf(context);
  List<String> get hand =>
      (c.table['hand'] as List? ?? []).map((x) => '$x').toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    unawaited(c.initialize());
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (!hand.contains(tile)) tile = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ([
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ].contains(state)) {
      c.background();
    } else if (state == AppLifecycleState.resumed) {
      c.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    c.dispose();
    super.dispose();
  }

  Future<void> leave() async {
    if (leaving) return;
    final ok =
        c.table['phase'] == 'closed' ||
        !widget.client.available ||
        await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Leave this table?'),
                content: Text(
                  c.table['phase'] == 'playing'
                      ? 'Leaving ends this round for everyone. Your camera and microphone will stop.'
                      : 'Your camera and microphone will stop. If you are the host, this closes the table.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Stay'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Leave table'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!ok || !mounted) return;
    setState(() => leaving = true);
    try {
      await c.leave();
    } catch (_) {
      await c.stopVideo();
    }
    if (mounted) {
      setState(() => pop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> invite() async {
    if (inviting) return;
    final peer = await showModalBottomSheet<SocialMap>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InvitePlayers(
        client: widget.client,
        existing: c.players.map((p) => '${p['id']}').toSet(),
      ),
    );
    if (peer == null || !mounted || !c.available) return;
    setState(() => inviting = true);
    try {
      await widget.client.post('domino', {
        'action': 'invite',
        'id': c.id,
        'peer': peer['id'],
      });
      await c.sync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Table invitation sent to ${peer['name']}.')),
        );
      }
    } catch (e) {
      if (mounted) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => inviting = false);
    }
  }

  void rules() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Block dominoes'),
      content: const SingleChildScrollView(
        child: Text(
          'Each player gets seven double-six tiles. With two players, unused tiles stay out of the round; there is no drawing.\n\nThe highest dealt double opens. If no double was dealt, the highest total tile opens. Play proceeds through the numbered seats.\n\nMatch a tile to either open end. Pass only when you have no legal move.\n\nFour-player teams use opposite seats: 1 + 3 versus 2 + 4. The first player out wins for their team. If everyone passes, the lowest combined remaining pip total wins; an equal total is a draw.\n\nThe winner earns the opponents’ remaining pip total. Wins and points stay at this table and have no cash value.\n\nEveryone selects Ready before the host deals each round. Cameras are optional. Leaving an active round closes the table.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
  String name(String? id) =>
      '${c.players.where((p) => p['id'] == id).firstOrNull?['name'] ?? 'Player'}';
  Widget videoSeat(int seat) {
    final p = c.players
        .where((p) => p['state'] == 'joined' && p['seat'] == seat)
        .firstOrNull;
    final own = p?['id'] == c.me, m = c.media;
    final renderer = own ? m?.local : m?.peers[p?['id']]?.renderer;
    final show =
        renderer?.srcObject != null &&
        (own
            ? m?.camera == true
            : p?['camera'] == true && p?['mediaSession'] != null);
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(
          right: seat == (c.table['capacity'] as num? ?? 2).toInt() - 1 ? 0 : 7,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: skin.panelDeep,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: c.table['turn'] == p?['id'] && p != null
                  ? const Color(0xFF65E7C6)
                  : skin.border,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (show)
                      rtc.RTCVideoView(
                        renderer!,
                        mirror: own,
                        objectFit: rtc
                            .RTCVideoViewObjectFit
                            .RTCVideoViewObjectFitCover,
                      )
                    else
                      Center(
                        child: p == null
                            ? Icon(
                                Icons.person_add_alt_1_rounded,
                                color: skin.mutedText,
                              )
                            : SocialAvatar(
                                member: p,
                                size: 32,
                                showStatus: false,
                              ),
                      ),
                    Positioned(
                      left: 5,
                      top: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${seat + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    if (p != null)
                      Positioned(
                        right: 5,
                        bottom: 4,
                        child: Icon(
                          (own
                                  ? m?.microphone == true
                                  : p['microphone'] == true &&
                                        p['mediaSession'] != null)
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: Text(
                  p == null
                      ? 'Open seat'
                      : own
                      ? 'You'
                      : '${p['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: skin.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget control(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool selected = false,
  }) => IconButton.filledTonal(
    tooltip: label,
    onPressed: onPressed,
    isSelected: selected,
    style: IconButton.styleFrom(
      backgroundColor: selected
          ? skin.secondary.withValues(alpha: .22)
          : skin.panelSoft,
      foregroundColor: selected ? skin.secondary : skin.text,
    ),
    icon: Icon(icon, size: 20),
  );
  Widget videos({bool sidebar = false}) => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
    decoration: BoxDecoration(
      color: skin.panel,
      border: Border(bottom: BorderSide(color: skin.border)),
    ),
    child: Column(
      children: [
        if (sidebar)
          for (
            var row = 0;
            row < ((c.table['capacity'] as num? ?? 2).toInt() / 2).ceil();
            row++
          )
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: SizedBox(
                height: 85,
                child: Row(
                  children: [videoSeat(row * 2), videoSeat(row * 2 + 1)],
                ),
              ),
            )
        else
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 500 ? 100 : 132,
            child: Row(
              children: [
                for (
                  var i = 0;
                  i < (c.table['capacity'] as num? ?? 2).toInt();
                  i++
                )
                  videoSeat(i),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (c.media == null)
          Row(
            children: [
              Expanded(
                child: KorlixActionButton(
                  key: const Key('domino-join-video'),
                  label: c.connectingVideo
                      ? 'Opening camera…'
                      : 'Join video & audio',
                  icon: Icons.video_call_rounded,
                  onPressed:
                      c.connectingVideo ||
                          !c.available ||
                          c.table['phase'] == 'closed'
                      ? null
                      : () => c.startVideo(),
                  size: KorlixButtonSize.compact,
                  expand: true,
                ),
              ),
              const SizedBox(width: 8),
              control('Game rules', Icons.info_outline_rounded, rules),
            ],
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              control(
                c.media!.microphone ? 'Mute microphone' : 'Unmute microphone',
                c.media!.microphone ? Icons.mic_rounded : Icons.mic_off_rounded,
                c.connectingVideo ? null : () => c.mediaControl('mic'),
                selected: c.media!.microphone,
              ),
              control(
                c.media!.camera ? 'Turn camera off' : 'Turn camera on',
                c.media!.camera
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                c.connectingVideo ? null : () => c.mediaControl('camera'),
                selected: c.media!.camera,
              ),
              control(
                'Switch camera',
                Icons.cameraswitch_outlined,
                c.connectingVideo ? null : () => c.mediaControl('flip'),
              ),
              control(
                c.media!.outputs.first.canRouteSpeaker
                    ? 'Speakerphone'
                    : 'Resume sound',
                Icons.volume_up_rounded,
                () => c.mediaControl('sound'),
                selected: c.media!.outputs.first.selected,
              ),
              control(
                'Reconnect video',
                Icons.refresh_rounded,
                c.connectingVideo ? null : () => c.reconnectVideo(),
              ),
              control(
                'Leave video',
                Icons.call_end_rounded,
                () => c.stopVideo(),
              ),
              control('Game rules', Icons.info_outline_rounded, rules),
            ],
          ),
      ],
    ),
  );
  Widget waiting() => SocialPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Your table is open.',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          'Invite friends, join video and select Ready. The host deals when every seat is ready.',
          style: TextStyle(color: skin.mutedText, height: 1.5),
        ),
        const SizedBox(height: 18),
        for (final p in c.players)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SocialAvatar(member: p, size: 34, showStatus: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${p['name']}${p['seat'] != null ? ' · Seat ${(p['seat'] as num).toInt() + 1}' : ''}',
                  ),
                ),
                Text(
                  p['state'] == 'invited'
                      ? 'Invited'
                      : p['ready'] == true
                      ? 'Ready'
                      : 'Not ready',
                  style: TextStyle(
                    color: p['ready'] == true ? skin.success : skin.mutedText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        if (c.table['host'] == c.me)
          KorlixActionButton(
            label: 'Invite a connection',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: inviting ? null : invite,
            expand: true,
          ),
        const SizedBox(height: 18),
        const DominoBoard(tiles: []),
      ],
    ),
  );
  Widget scoreboard() {
    final teams = (c.table['capacity'] as num?) == 4;
    final wins = socialMap(c.table['wins']),
        points = socialMap(c.table['points']);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final key
            in teams
                ? ['team0', 'team1']
                : c.players
                      .where((p) => p['state'] == 'joined')
                      .map((p) => '${p['id']}'))
          Chip(
            label: Text(
              '${teams ? (key == 'team0' ? 'Seats 1 + 3' : 'Seats 2 + 4') : name(key)} · ${wins[key] ?? 0} wins · ${points[key] ?? 0} pts',
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget game() {
    final board = socialItems(c.table['board']),
        result = socialMap(c.table['result']);
    final winner = result['winner'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        scoreboard(),
        const SizedBox(height: 12),
        if (c.table['phase'] == 'finished')
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: SocialPanel(
              accent: skin.success,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    winner == null
                        ? 'A tied round.'
                        : winner == 'team0'
                        ? 'Seats 1 + 3 win!'
                        : winner == 'team1'
                        ? 'Seats 2 + 4 win!'
                        : '${name(winner)} wins!',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${result['reason'] == 'blocked' ? 'The table was blocked.' : 'All tiles played.'} ${result['points'] ?? 0} points this round.',
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Select Ready for another round.',
                    style: TextStyle(color: skin.mutedText),
                  ),
                ],
              ),
            ),
          ),
        Text(
          'ROUND ${c.table['round']}  /  ${c.table['phase'] == 'finished'
              ? 'COMPLETE'
              : c.myTurn
              ? 'YOUR TURN'
              : '${name(c.table['turn'])}’S TURN'}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: c.myTurn ? skin.success : skin.secondary,
          ),
        ),
        const SizedBox(height: 12),
        DominoBoard(tiles: board),
        const SizedBox(height: 12),
        if (board.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Left end: ${board.first['a']}',
                style: TextStyle(color: skin.mutedText),
              ),
              Text(
                'Right end: ${board.last['b']}',
                style: TextStyle(color: skin.mutedText),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            '${c.table['last'] ?? ''}',
            style: TextStyle(color: skin.mutedText, fontSize: 13),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            for (final p in c.players.where(
              (p) => p['state'] == 'joined' && p['id'] != c.me,
            ))
              Text(
                '${p['name']}: ${p['count']} tiles${p['online'] == true ? '' : ' · away'}',
                style: TextStyle(color: skin.mutedText, fontSize: 12),
              ),
          ],
        ),
      ],
    );
  }

  Widget handBar() {
    final phase = c.table['phase'],
        legal = socialItems(c.table['legal']),
        active = c.myTurn && !c.busy;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: skin.panelDeep,
          border: Border(top: BorderSide(color: skin.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (phase == 'waiting' || phase == 'finished')
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  KorlixActionButton(
                    key: const Key('domino-ready'),
                    label: c.mine?['ready'] == true ? 'Ready ✓' : 'I’m ready',
                    icon: Icons.check_circle_outline_rounded,
                    selected: c.mine?['ready'] == true,
                    onPressed: c.busy || !c.fresh
                        ? null
                        : () =>
                              c.move('ready', ready: c.mine?['ready'] != true),
                    size: KorlixButtonSize.compact,
                  ),
                  if (c.table['host'] == c.me)
                    KorlixActionButton(
                      key: const Key('domino-deal'),
                      label: phase == 'finished'
                          ? 'Deal next round'
                          : 'Deal tiles',
                      icon: Icons.style_rounded,
                      onPressed:
                          c.busy ||
                              !c.fresh ||
                              c.players
                                      .where((p) => p['state'] == 'joined')
                                      .length !=
                                  c.table['capacity'] ||
                              c.players
                                  .where((p) => p['state'] == 'joined')
                                  .any(
                                    (p) =>
                                        p['ready'] != true ||
                                        p['online'] != true,
                                  )
                          ? null
                          : () => c.move('start'),
                      size: KorlixButtonSize.compact,
                    ),
                ],
              )
            else if (phase == 'playing') ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      active ? 'YOUR HAND · TAP A GLOWING TILE' : 'YOUR HAND',
                      style: TextStyle(
                        color: active ? skin.success : skin.mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  if (c.busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (_, box) {
                  final compact = MediaQuery.sizeOf(context).height < 500;
                  final width = math.min(
                    compact ? 34.0 : 48.0,
                    (box.maxWidth - 36) / 7,
                  );
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final value in hand) ...[
                        if (value != hand.first) const SizedBox(width: 6),
                        DominoTile(
                          key: Key('domino-tile-$value'),
                          a: int.parse(value.split('-')[0]),
                          b: int.parse(value.split('-')[1]),
                          width: width,
                          selected: tile == value,
                          playable:
                              active && legal.any((m) => m['tile'] == value),
                          onTap: active && legal.any((m) => m['tile'] == value)
                              ? () => setState(() => tile = value)
                              : null,
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              if (active && legal.isEmpty)
                KorlixActionButton(
                  key: const Key('domino-pass'),
                  label: 'No matching tile · Pass',
                  icon: Icons.skip_next_rounded,
                  onPressed: () => c.move('pass'),
                  expand: true,
                  size: KorlixButtonSize.compact,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('domino-left'),
                        onPressed:
                            active &&
                                legal.any(
                                  (m) =>
                                      m['tile'] == tile && m['side'] == 'left',
                                )
                            ? () => c.move('play', tile: tile, side: 'left')
                            : null,
                        icon: const Icon(Icons.west_rounded),
                        label: const Text('Play left'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('domino-right'),
                        onPressed:
                            active &&
                                legal.any(
                                  (m) =>
                                      m['tile'] == tile && m['side'] == 'right',
                                )
                            ? () => c.move('play', tile: tile, side: 'right')
                            : null,
                        icon: const Icon(Icons.east_rounded),
                        label: Text(
                          socialItems(c.table['board']).isEmpty
                              ? 'Open round'
                              : 'Play right',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
            if (!c.fresh && phase != 'closed')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Reconnecting to the table…',
                  style: TextStyle(color: skin.premium, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: pop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(leave());
    },
    child: Scaffold(
      backgroundColor: skin.backgroundBottom,
      appBar: AppBar(
        title: Text(
          '${c.table['name'] ?? 'Dominoes'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh table',
            onPressed: () => c.sync(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Leave table',
            onPressed: leaving ? null : leave,
            icon: const Icon(Icons.exit_to_app_rounded),
          ),
        ],
      ),
      body: !c.available
          ? Center(
              child: Text(
                'Sign in again to play.',
                style: TextStyle(color: skin.text),
              ),
            )
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: LayoutBuilder(
                    builder: (_, box) {
                      final board = ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (c.videoError != null ||
                              c.media?.issue.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Text(
                                c.videoError ?? c.media!.issue,
                                style: TextStyle(
                                  color: skin.premium,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (c.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                c.error!,
                                style: TextStyle(color: skin.danger),
                              ),
                            ),
                          if (c.table['phase'] == 'closed')
                            SocialPanel(
                              child: Column(
                                children: [
                                  const Text(
                                    'This table is closed.',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text('${c.table['last'] ?? ''}'),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    onPressed: leave,
                                    child: const Text('Back to tables'),
                                  ),
                                ],
                              ),
                            )
                          else if (c.table['phase'] == 'waiting')
                            waiting()
                          else
                            game(),
                        ],
                      );
                      final landscape =
                          box.maxWidth > 650 && box.maxHeight < 500;
                      final playing = Column(
                        children: [
                          Expanded(child: board),
                          if (c.table['phase'] != 'closed') handBar(),
                        ],
                      );
                      if (landscape) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 240,
                              child: SingleChildScrollView(
                                child: videos(sidebar: true),
                              ),
                            ),
                            Expanded(child: playing),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          videos(),
                          Expanded(child: playing),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
    ),
  );
}

class _InvitePlayers extends StatefulWidget {
  const _InvitePlayers({required this.client, required this.existing});
  final SocialClient client;
  final Set<String> existing;
  @override
  State<_InvitePlayers> createState() => _InvitePlayersState();
}

class _InvitePlayersState extends State<_InvitePlayers> {
  final search = TextEditingController();
  List<SocialMap> people = [];
  bool loading = false, more = false;
  String? error;
  int offset = 0;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool next = false}) async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final at = next ? offset + 40 : 0;
      final r = await widget.client.get('connections', {
        'state': 'accepted',
        'q': search.text.trim(),
        'offset': at,
      });
      if (!mounted) return;
      final rows = socialItems(r['items']);
      setState(() {
        people = [if (next) ...people, ...rows.take(40)];
        offset = at;
        more = rows.length > 40;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Invite a connection',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text('Choose a friend to join your private table.'),
            const SizedBox(height: 14),
            TextField(
              controller: search,
              onSubmitted: (_) => load(),
              decoration: InputDecoration(
                labelText: 'Search connections',
                suffixIcon: IconButton(
                  onPressed: loading ? null : () => load(),
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            Expanded(
              child: ListView(
                children: [
                  for (final p in people)
                    ListTile(
                      leading: SocialAvatar(
                        member: p,
                        size: 36,
                        showStatus: false,
                      ),
                      title: Text('${p['name']}'),
                      subtitle: Text('@${p['handle']}'),
                      trailing: widget.existing.contains(p['id'])
                          ? const Text('Invited')
                          : const Icon(Icons.add_rounded),
                      enabled: !widget.existing.contains(p['id']),
                      onTap: () => Navigator.pop(context, p),
                    ),
                  if (people.isEmpty && !loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No matching connections. Accept a follow request in Social first.',
                      ),
                    ),
                  if (more)
                    TextButton(
                      onPressed: loading ? null : () => load(next: true),
                      child: const Text('Load more'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
