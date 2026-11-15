import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../services/vanity_sync.dart';
import 'account.dart';
import 'brand.dart';
import 'voice.dart';

export 'brand.dart' show eshaTheme;

class EshaApp extends StatefulWidget {
  const EshaApp({super.key, required this.controller});
  final EshaController controller;
  @override
  State<EshaApp> createState() => _EshaAppState();
}

class _EshaAppState extends State<EshaApp> {
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Esha by Korlix',
    debugShowCheckedModeBanner: false,
    theme: eshaTheme,
    home: EshaHome(controller: widget.controller),
  );
}

class EshaHome extends StatefulWidget {
  const EshaHome({super.key, required this.controller});
  final EshaController controller;
  @override
  State<EshaHome> createState() => _EshaHomeState();
}

class _EshaHomeState extends State<EshaHome> with WidgetsBindingObserver {
  int selected = 0;
  EshaController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A permission dialog can be inactive without being backgrounded. Stop on
    // hidden/paused/detached, then require an explicit user action to resume.
    if (state != AppLifecycleState.inactive || !c.voice.requestingMicrophone) {
      c.voice.setForeground(state == AppLifecycleState.resumed);
    }
    c.purchases.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && !c.initializing) {
      c.purchases.refresh();
    }
  }

  void go(int index) {
    if (selected == 1 && index != 1 && c.voice.canStop) c.voice.pause();
    setState(() => selected = index);
  }

  void membership() {
    if (c.voice.canStop) c.voice.pause();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MembershipScreen(controller: c)),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => !c.initializing && !c.hasAppAccess
        ? MembershipScreen(controller: c)
        : Scaffold(
            appBar: AppBar(
              toolbarHeight: 83,
              titleSpacing: 22,
              title: const Wordmark(),
              actions: [
                IconButton(
                  tooltip: 'Esha membership',
                  onPressed: membership,
                  icon: const Icon(Icons.auto_awesome_outlined),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton(
                    tooltip: c.session == null
                        ? 'Sign in and beauty profile'
                        : 'Account and beauty profile',
                    onPressed: () {
                      if (c.voice.canStop) c.voice.pause();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AccountScreen(controller: c),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_outline),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: c.initializing
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        if (c.notice != null)
                          MaterialBanner(
                            content: Text(c.notice!),
                            actions: [
                              TextButton(
                                onPressed: c.clearNotice,
                                child: const Text('Dismiss'),
                              ),
                            ],
                          ),
                        Expanded(
                          child: IndexedStack(
                            index: selected,
                            children: [
                              DiscoverScreen(
                                controller: c,
                                onConsult: () => go(1),
                                onMembership: membership,
                              ),
                              ConsultScreen(
                                controller: c,
                                onMembership: membership,
                              ),
                              StudioScreen(controller: c),
                              VanityScreen(
                                controller: c,
                                onDiscover: () => go(0),
                                onConsult: () => go(1),
                                onStudio: () => go(2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: go,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Discover',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome),
                  label: 'Ask Esha',
                ),
                NavigationDestination(
                  icon: Icon(Icons.face_retouching_natural_outlined),
                  selectedIcon: Icon(Icons.face_retouching_natural),
                  label: 'Try a Look',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_border),
                  selectedIcon: Icon(Icons.favorite),
                  label: 'My Vanity',
                ),
              ],
            ),
          ),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.controller,
    required this.onConsult,
    required this.onMembership,
  });
  final EshaController controller;
  final VoidCallback onConsult, onMembership;
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  String category = 'All', query = '';
  @override
  Widget build(BuildContext context) =>
      EntitledContent(controller: widget.controller, builder: _buildContent);
  Widget _buildContent(BuildContext context) {
    final c = widget.controller;
    final products = c.catalog.products
        .where(
          (p) =>
              (category == 'All' || p.category == category) &&
              '${p.name} ${p.brand} ${p.category}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return PageBody(
      children: [
        EshaPanel(
          color: plum,
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text(
                      'A LITTLE BEAUTY,\nALL YOUR OWN.',
                      style: TextStyle(
                        color: Color(0xFFE8B9CD),
                        letterSpacing: 2,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.7,
                      ),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/esha-korlix-pink.png',
                      width: 64,
                      height: 64,
                      semanticLabel: 'Pink Korlix logo',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Your beauty.\nYour way.',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 39,
                  height: 1.1,
                  color: Color(0xFFFFF6ED),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Makeup, lips, lashes & body care.\nA thoughtful edit, made around you.',
                style: TextStyle(color: Color(0xFFE5CFD8), height: 1.6),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: widget.onConsult,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE8B9CD),
                  foregroundColor: plum,
                ),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Find my beauty edit'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const PageHeading(
          'THE BEAUTY SHELF',
          'Discover your next favorite',
          'A small, sourced collection. Explore the details, then make it yours.',
        ),
        TextField(
          key: const Key('catalog-search'),
          decoration: const InputDecoration(
            hintText: 'Search products or brands',
            prefixIcon: Icon(Icons.search),
            labelText: 'Search the beauty shelf',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', ...Catalog.categories]
                .map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: category == name,
                      onSelected: (_) => setState(() => category = name),
                      selectedColor: blush,
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 8,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
        if (products.isEmpty)
          const EshaPanel(
            child: Text(
              'No products match that search. Try another name or category.',
            ),
          )
        else
          ProductGrid(products: products, controller: c),
        const SizedBox(height: 24),
        EshaPanel(
          color: blush,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Meet your beauty companion',
                style: TextStyle(fontFamily: 'Georgia', fontSize: 23),
              ),
              const SizedBox(height: 8),
              const Text(
                'Esha membership is being prepared: 3 days free for eligible subscribers, then US \$4.99 per month. Your store will show the available offer and local price.',
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onMembership,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('View membership'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Manufacturer price snapshots · ${c.catalog.checkedAt}\nProduct estimates exclude tax and shipping. Availability is unverified. Product artwork is illustrative.',
          style: const TextStyle(fontSize: 11, color: muted, height: 1.6),
        ),
      ],
    );
  }
}

class ConsultScreen extends StatefulWidget {
  const ConsultScreen({
    super.key,
    required this.controller,
    required this.onMembership,
  });
  final EshaController controller;
  final VoidCallback onMembership;
  @override
  State<ConsultScreen> createState() => _ConsultScreenState();
}

class _ConsultScreenState extends State<ConsultScreen> {
  bool live = false;
  bool voice = false;
  final question = TextEditingController();
  late int _questionEpoch;
  @override
  void initState() {
    super.initState();
    _questionEpoch = widget.controller.accountEpoch;
  }

  @override
  void didUpdateWidget(covariant ConsultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_questionEpoch != widget.controller.accountEpoch) {
      _questionEpoch = widget.controller.accountEpoch;
      question.clear();
      live = false;
      voice = false;
    }
  }

  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      EntitledContent(controller: widget.controller, builder: _buildContent);
  Widget _buildContent(BuildContext context) {
    final c = widget.controller, prefs = widget.controller.vanity.prefs;
    return PageBody(
      children: [
        const PageHeading(
          'YOUR BEAUTY COMPANION',
          'Let’s find your edit.',
          'Start with what you love, what you own and the budget that works for you.',
        ),
        Wrap(
          spacing: 10,
          children: [
            ChoiceChip(
              label: const Text('Guided beauty edit'),
              selected: !live && !voice,
              onSelected: (_) => setState(() {
                live = false;
                voice = false;
              }),
              padding: const EdgeInsets.all(10),
            ),
            ChoiceChip(
              label: const Text('Chat with Esha'),
              selected: live && !voice,
              onSelected: (_) => setState(() {
                live = true;
                voice = false;
              }),
              padding: const EdgeInsets.all(10),
            ),
            ChoiceChip(
              label: const Text('Voice with Esha'),
              selected: voice,
              onSelected: (_) => setState(() => voice = true),
              padding: const EdgeInsets.all(10),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (voice)
          EshaVoicePanel(controller: c.voice)
        else if (live)
          ..._liveChat(c)
        else ...[
          EshaPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChoiceGroup(
                  label: 'What are we creating?',
                  options: const {
                    'look': 'Makeup look',
                    'body': 'Body ritual',
                    'lips': 'Lip pairing',
                    'lashes': 'Lash edit',
                  },
                  value: prefs.goal,
                  onChanged: c.canEditCollection
                      ? (v) => c.setPreferences(prefs.copyWith(goal: v))
                      : null,
                ),
                const SizedBox(height: 24),
                Text(
                  'New-product budget · ${usd(prefs.budget * 100)} USD',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Slider(
                  value: prefs.budget.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 90,
                  label: usd(prefs.budget * 100),
                  semanticFormatterCallback: (v) => '${v.round()} US dollars',
                  onChanged: c.canEditCollection
                      ? (v) =>
                            c.setPreferences(prefs.copyWith(budget: v.round()))
                      : null,
                ),
                const Text(
                  'Product prices only, before tax and shipping.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 22),
                if (prefs.goal == 'body') ...[
                  ChoiceGroup(
                    label: 'Fragrance preference',
                    options: const {
                      'none': 'Fragrance-free',
                      'any': 'Open to fragrance',
                    },
                    value: prefs.fragrance,
                    onChanged: c.canEditCollection
                        ? (v) => c.setPreferences(prefs.copyWith(fragrance: v))
                        : null,
                  ),
                  const SizedBox(height: 18),
                  ChoiceGroup(
                    label: 'Lotion texture',
                    options: const {
                      'light': 'Light & silky',
                      'rich': 'Rich',
                      'any': 'Any texture',
                    },
                    value: prefs.bodyTexture,
                    onChanged: c.canEditCollection
                        ? (v) =>
                              c.setPreferences(prefs.copyWith(bodyTexture: v))
                        : null,
                  ),
                ] else
                  ChoiceGroup(
                    label: 'Finish preference',
                    options: const {
                      'natural': 'Natural',
                      'dewy': 'Dewy',
                      'satin': 'Satin',
                      'matte': 'Matte',
                      'any': 'Any finish',
                    },
                    value: prefs.finish,
                    onChanged: c.canEditCollection
                        ? (v) => c.setPreferences(prefs.copyWith(finish: v))
                        : null,
                  ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use what I own'),
                  subtitle: const Text(
                    'Owned products add no new purchase cost.',
                  ),
                  value: prefs.useOwned,
                  onChanged: c.canEditCollection
                      ? (v) => c.setPreferences(prefs.copyWith(useOwned: v))
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _recommendation(c),
          const SizedBox(height: 18),
          const Text(
            'This guided edit uses documented product attributes and your selections. It does not infer your skin tone or guarantee ingredients, allergy safety or an exact shade match.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ],
    );
  }

  Widget _recommendation(EshaController c) {
    final result = c.recommendation;
    if (!result.complete) {
      return EshaPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.reason == 'budget'
                  ? 'A little more room?'
                  : 'No complete edit just yet.',
              style: const TextStyle(fontFamily: 'Georgia', fontSize: 24),
            ),
            const SizedBox(height: 10),
            Text(
              result.reason == 'budget'
                  ? 'The lowest-priced complete selection is ${usd(result.minimumCents!)} USD. Your ${usd(c.vanity.prefs.budget * 100)} budget does not cover it before tax and shipping.'
                  : 'The sourced collection does not have a priced option for ${result.unavailable.join(' and ')} with these preferences.',
            ),
            if (result.reason == 'budget' && result.minimumCents! <= 10000) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => c.setPreferences(
                  c.vanity.prefs.copyWith(
                    budget: (result.minimumCents! / 100).ceil(),
                  ),
                ),
                child: Text(
                  'Try ${usd((result.minimumCents! / 100).ceil() * 100)}',
                ),
              ),
            ],
          ],
        ),
      );
    }
    return EshaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            goals[c.vanity.prefs.goal]!.title,
            style: const TextStyle(fontFamily: 'Georgia', fontSize: 25),
          ),
          const SizedBox(height: 8),
          Text(
            goals[c.vanity.prefs.goal]!.description,
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < result.items.length; i++) ...[
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: blush,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: pink, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.items[i].brand,
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                      Text(
                        result.items[i].name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        recommendationReason(result.items[i], c.vanity),
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.vanity.prefs.useOwned &&
                                c.vanity.owned.contains(result.items[i].id)
                            ? '\$0.00 new cost · Owned'
                            : result.items[i].priceLabel,
                        style: const TextStyle(
                          color: pink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            showProduct(context, result.items[i], c),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        child: const Text('Check shade, size & details ↗'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 26),
          Text(
            'New products estimate: ${usd(result.costCents)} USD',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 5),
          Text(
            '${usd(c.vanity.prefs.budget * 100 - result.costCents)} left before tax and shipping',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: c.canEditCollection
                  ? () {
                      if (c.saveRoutine()) {
                        showMessage(
                          context,
                          'Saved this exact edit to My Vanity.',
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.bookmark_border),
              label: const Text('Save my edit'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _liveChat(EshaController c) => [
    EshaPanel(
      color: blush,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Beauty advice, with context.',
            style: TextStyle(fontFamily: 'Georgia', fontSize: 24),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ask about makeup, lip pairings, lashes or a body-care routine. Esha uses the sourced product catalog and the preferences you choose to share.',
          ),
          const SizedBox(height: 12),
          Text(
            c.vanity.beautyProfile.shareWithEsha
                ? 'Beauty preferences are shared with your questions.'
                : 'Your beauty profile is not shared. You can change this in your profile.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const Divider(height: 28),
          const Text(
            'Your choice before live AI advice',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'To answer live questions, Korlix sends your question and recent conversation to OpenAI, its AI service provider. Beauty preferences are included only when you choose to share them in your profile. No camera image is sent.',
            style: TextStyle(fontSize: 13),
          ),
          CheckboxListTile(
            key: const ValueKey('esha-ai-sharing-consent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: c.aiSharingConsented,
            onChanged: c.session == null
                ? null
                : (value) => c.setAiSharingConsent(value == true),
            title: const Text(
              'I allow this information to be shared with OpenAI for live answers.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          Text(
            c.session == null ? 'Sign in before making this choice.' : 'This choice applies to your current signed-in session on this device. Turn it off to stop future questions and retries. Information already sent cannot be recalled.',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          TextButton(
            onPressed: () =>
                openSource(context, '${c.api.config.apiOrigin}/esha/privacy'),
            child: const Text('Read Esha Privacy Policy'),
          ),
          if (c.purchases.membership.allowanceLimit != null) ...[
            const SizedBox(height: 10),
            Text(
              '${c.purchases.membership.remaining ?? 0} of ${c.purchases.membership.allowanceLimit} consultations remaining',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if (!c.purchases.canConsult)
            TextButton(
              onPressed: widget.onMembership,
              child: Text(
                c.session == null
                    ? 'Sign in & view membership'
                    : 'View membership & allowance',
              ),
            ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    if (c.chat.isEmpty && !c.hasPendingQuestion)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Try: “Build a simple satin makeup routine around products I own.”',
          style: TextStyle(color: muted, fontStyle: FontStyle.italic),
        ),
      ),
    for (final turn in c.chat)
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: EshaPanel(
          color: turn.role == 'user' ? blush : Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                turn.role == 'user' ? 'YOU' : 'ESHA',
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: pink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(turn.content),
              if (turn.role == 'assistant') ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  key: ValueKey('esha-report-${turn.requestId}'),
                  onPressed:
                      c.isReporting(turn) || c.reportReceiptFor(turn) != null
                      ? null
                      : () => _reportAnswer(turn),
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(
                    c.reportReceiptFor(turn) != null
                        ? 'Report received'
                        : 'Report this answer',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    if (c.hasPendingQuestion)
      EshaPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'YOUR PENDING QUESTION',
              style: TextStyle(color: pink, fontSize: 10, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            Text(c.pendingQuestion ?? ''),
            const SizedBox(height: 8),
            c.chatBusy
                ? const LinearProgressIndicator()
                : OutlinedButton.icon(
                    onPressed: c.hasAppAccess && c.aiSharingConsented
                        ? c.retryQuestion
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry this question'),
                  ),
          ],
        ),
      ),
    if (c.chatError != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(c.chatError!, style: const TextStyle(color: pink)),
      ),
    if (!c.hasPendingQuestion) ...[
      TextField(
        controller: question,
        minLines: 2,
        maxLines: 6,
        maxLength: 3000,
        enabled: !c.chatBusy,
        decoration: const InputDecoration(
          labelText: 'Your beauty question',
          hintText: 'What would you like help with?',
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed:
              c.aiSharingConsented && c.purchases.canConsult && !c.chatBusy
              ? () {
                  final text = question.text;
                  c.ask(text);
                  if (text.trim().isNotEmpty) question.clear();
                }
              : null,
          icon: const Icon(Icons.arrow_upward),
          label: const Text('Ask Esha'),
        ),
      ),
    ],
    const SizedBox(height: 18),
    const Text(
      'Esha is an AI beauty consultant. Check product details before purchase. Live answers require a verified Esha membership and available consultations. No camera image is used.',
      style: TextStyle(fontSize: 11, color: muted),
    ),
  ];

  Future<void> _reportAnswer(ChatTurn turn) async {
    final c = widget.controller;
    try {
      final evidence = c.reportEvidence(turn);
      final receipt = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ReportAnswerDialog(controller: c, turn: turn, evidence: evidence),
      );
      if (mounted && receipt != null) {
        showMessage(context, 'Report received for review. Reference: $receipt');
      }
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          error is EshaException
              ? error.message
              : 'This answer could not be reported. Please try again.',
        );
      }
    }
  }
}

class ReportAnswerDialog extends StatefulWidget {
  const ReportAnswerDialog({
    super.key,
    required this.controller,
    required this.turn,
    required this.evidence,
  });
  final EshaController controller;
  final ChatTurn turn;
  final AnswerReportEvidence evidence;
  @override
  State<ReportAnswerDialog> createState() => _ReportAnswerDialogState();
}

class _ReportAnswerDialogState extends State<ReportAnswerDialog> {
  final details = TextEditingController();
  String reason = eshaReportReasons.first;
  String? error;
  bool sending = false;
  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !sending,
    child: AlertDialog(
      title: const Text('Report this answer'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sending a report shares the answer and paired question shown below, your selected reason, and any details you add with Korlix support. Your signed-in account identifies the report. Nothing is sent until you tap Send report.',
            ),
            if (widget.evidence.shortened) ...[
              const SizedBox(height: 12),
              const Text(
                'This is a long conversation item. The report includes only the beginning shown below to fit the report size limit. Describe a later passage in Details if needed.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              constraints: const BoxConstraints(maxHeight: 210),
              padding: const EdgeInsets.all(12),
              color: blush,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'QUESTION',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(widget.evidence.question),
                    const SizedBox(height: 12),
                    const Text(
                      'ANSWER INCLUDED IN REPORT',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(widget.evidence.answer),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: reason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: eshaReportReasons
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: sending
                  ? null
                  : (value) => setState(() => reason = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: details,
              enabled: !sending,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                hintText: 'Tell support what concerned you.',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!, style: const TextStyle(color: pink)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: sending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: sending ? null : _send,
          child: Text(sending ? 'Sending…' : 'Send report'),
        ),
      ],
    ),
  );

  Future<void> _send() async {
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final receipt = await widget.controller.reportAnswer(
        widget.turn,
        reason: reason,
        details: details.text,
      );
      if (mounted) Navigator.pop(context, receipt);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure is EshaException
              ? failure.message
              : 'The report could not be confirmed. Please try again later.';
        });
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
}

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key, required this.controller});
  final EshaController controller;
  @override
  Widget build(BuildContext context) =>
      EntitledContent(controller: controller, builder: _buildContent);
  Widget _buildContent(BuildContext context) {
    final c = controller, look = controller.vanity.studio;
    return PageBody(
      children: [
        const PageHeading(
          'THE LOOK STUDIO',
          'Play with a little color.',
          'Explore a lip finish and lash mood, then save the combination you love.',
        ),
        EshaPanel(
          color: blush,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Semantics(
                label:
                    'Stylized beauty illustration with ${lookNames[look.shade]} lips, ${look.finish.toLowerCase()} finish and ${look.lashes.toLowerCase()} lashes',
                child: SizedBox(
                  height: 340,
                  width: double.infinity,
                  child: CustomPaint(painter: LookPainter(look)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Text(
                  'ILLUSTRATIVE COLOR STUDY · NOT A SELFIE TRY-ON',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.1,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        EshaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lip mood',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: List.generate(
                  4,
                  (i) => Semantics(
                    selected: look.shade == i,
                    label: '${lookNames[i]} lip color',
                    button: true,
                    child: InkWell(
                      onTap: c.canEditCollection
                          ? () => c.setStudio(look.copyWith(shade: i))
                          : null,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: lookColors[i],
                                border: Border.all(
                                  color: look.shade == i
                                      ? plum
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: look.shade == i
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              lookNames[i],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ChoiceGroup(
                label: 'Lip finish',
                options: const {'Satin': 'Satin', 'Gloss': 'Gloss'},
                value: look.finish,
                onChanged: c.canEditCollection
                    ? (v) => c.setStudio(look.copyWith(finish: v))
                    : null,
              ),
              const SizedBox(height: 20),
              ChoiceGroup(
                label: 'Lash mood',
                options: const {
                  'Soft': 'Soft',
                  'Wispy': 'Wispy',
                  'Bold': 'Bold',
                },
                value: look.lashes,
                onChanged: c.canEditCollection
                    ? (v) => c.setStudio(look.copyWith(lashes: v))
                    : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: c.canEditCollection
                      ? () {
                          if (c.saveLook()) {
                            showMessage(context, 'Look saved to My Vanity.');
                          }
                        }
                      : null,
                  icon: const Icon(Icons.favorite_border),
                  label: const Text('Save this look'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Colors are illustrative and are not tied to a product shade. Results do not predict how makeup will look on your face or skin tone.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}

class VanityScreen extends StatefulWidget {
  const VanityScreen({
    super.key,
    required this.controller,
    required this.onDiscover,
    required this.onConsult,
    required this.onStudio,
  });
  final EshaController controller;
  final VoidCallback onDiscover, onConsult, onStudio;
  @override
  State<VanityScreen> createState() => _VanityScreenState();
}

class _VanityScreenState extends State<VanityScreen> {
  String tab = 'favorites';
  @override
  Widget build(BuildContext context) =>
      EntitledContent(controller: widget.controller, builder: _buildContent);
  Widget _buildContent(BuildContext context) {
    final c = widget.controller;
    final products = c.catalog.products
        .where(
          (p) => (tab == 'favorites' ? c.vanity.favorites : c.vanity.owned)
              .contains(p.id),
        )
        .toList();
    return PageBody(
      children: [
        const PageHeading(
          'YOUR LITTLE BEAUTY SPACE',
          'My Vanity',
          'Your favorites, what you own and the edits you want to come back to.',
        ),
        SyncPanel(controller: c),
        const SizedBox(height: 22),
        ChoiceGroup(
          label: 'Your collection',
          options: {
            'favorites': 'Favorites (${c.vanity.favorites.length})',
            'owned': 'Owned (${c.vanity.owned.length})',
            'routines': 'Edits (${c.vanity.routines.length})',
            'looks': 'Looks (${c.vanity.looks.length})',
          },
          value: tab,
          onChanged: (value) => setState(() => tab = value),
        ),
        const SizedBox(height: 22),
        if (tab == 'favorites' || tab == 'owned')
          if (products.isNotEmpty)
            ProductGrid(products: products, controller: c)
          else
            _empty(
              tab == 'favorites'
                  ? 'Keep the ones you love.'
                  : 'Start with what you own.',
              tab == 'favorites'
                  ? 'Tap a heart in Discover to save a product here.'
                  : 'Mark products you own to include them in your guided edit at no new cost.',
              'Explore the beauty shelf',
              widget.onDiscover,
            ),
        if (tab == 'routines')
          if (c.vanity.routines.isEmpty)
            _empty(
              'Your next routine starts here.',
              'Create a guided edit and save the exact selection to revisit later.',
              'Create my edit',
              widget.onConsult,
            )
          else
            ...c.vanity.routines.map(
              (routine) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: EshaPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routine.name,
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${routine.ids.length} products · ${usd(routine.costCents)} USD at save',
                        style: const TextStyle(color: muted),
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () => _openRoutine(routine),
                            child: const Text('Open saved edit'),
                          ),
                          TextButton(
                            onPressed: () => c.deleteRoutine(routine.id),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (tab == 'looks')
          if (c.vanity.looks.isEmpty)
            _empty(
              'A mood worth saving.',
              'Play with an illustrative lip color, finish and lash combination.',
              'Open the look studio',
              widget.onStudio,
            )
          else
            ...c.vanity.looks.map(
              (look) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: EshaPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${lookNames[look.shade]} · ${look.finish}',
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 23,
                        ),
                      ),
                      Text(
                        '${look.lashes} lashes · illustrative color study',
                        style: const TextStyle(color: muted),
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () {
                              c.setStudio(look);
                              widget.onStudio();
                            },
                            child: const Text('Open saved look'),
                          ),
                          TextButton(
                            onPressed: () => c.deleteLook(look.id),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _empty(String title, String body, String action, VoidCallback onTap) =>
      EshaPanel(
        color: blush,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.favorite_border, color: pink, size: 30),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontFamily: 'Georgia', fontSize: 25),
            ),
            const SizedBox(height: 10),
            Text(body),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onTap, child: Text(action)),
          ],
        ),
      );
  void _openRoutine(SavedRoutine routine) {
    if (!widget.controller.hasAppAccess) return;
    final ownerId = widget.controller.session!.userId;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: ivory,
      builder: (context) => EntitledContent(
        controller: widget.controller,
        ownerId: ownerId,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  routine.name,
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 28),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This is the exact saved selection. Its prices and owned-product choices reflect the time it was saved.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                for (final id in routine.ids) _savedItem(routine, id),
                const Divider(height: 26),
                Text(
                  'Saved new-product estimate: ${usd(routine.costCents)} USD',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () {
                    widget.controller.setPreferences(routine.prefs);
                    Navigator.pop(context);
                    widget.onConsult();
                  },
                  child: const Text('Create a new edit with these preferences'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _savedItem(SavedRoutine routine, String id) {
    final matching = routine.items.where((p) => p['id'] == id).toList();
    final saved = matching.isEmpty ? <String, dynamic>{} : matching.first;
    final current = widget.controller.catalog.byId(id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            saved['name'] as String? ?? current?.name ?? 'Saved product: $id',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            routine.prefs.useOwned && routine.ownedAtSave.contains(id)
                ? 'Owned when saved · \$0.00 new cost'
                : saved['priceCents'] is int
                ? '${usd(saved['priceCents'] as int)} USD when saved'
                : 'Price not recorded',
            style: const TextStyle(color: muted),
          ),
          if (saved['sourceUrl'] is String)
            TextButton(
              onPressed: () =>
                  openSource(context, saved['sourceUrl'] as String),
              child: const Text('Manufacturer details ↗'),
            ),
        ],
      ),
    );
  }
}

class SyncPanel extends StatelessWidget {
  const SyncPanel({super.key, required this.controller});
  final EshaController controller;
  @override
  Widget build(BuildContext context) {
    final sync = controller.sync;
    final label = switch (sync.status) {
      SyncState.local => 'Guest collection · saved on this device',
      SyncState.loading => 'Loading your collection…',
      SyncState.saving => 'Saving to your Korlix account…',
      SyncState.saved => 'Synced with your Korlix account',
      SyncState.conflict => 'Another account version is available',
      SyncState.uncertain => 'Save awaiting confirmation',
      SyncState.offline => 'Local draft retained · sync paused',
    };
    return EshaPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sync.status == SyncState.saved
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_outlined,
                size: 22,
                color: pink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (controller.session == null) ...[
            const SizedBox(height: 8),
            const Text(
              'Sign in to sync a separate account collection. Your guest collection stays here.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
          if (sync.message != null) ...[
            const SizedBox(height: 8),
            Text(
              sync.message!,
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ],
          if ([
            SyncState.conflict,
            SyncState.uncertain,
            SyncState.offline,
          ].contains(sync.status))
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: sync.retry,
                  child: const Text('Retry sync'),
                ),
                TextButton(
                  onPressed: () async {
                    final replace = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Load the account version?'),
                        content: const Text(
                          'This replaces the local draft for this account with the latest saved account collection. Your guest collection stays separate.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Keep my draft'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Load account version'),
                          ),
                        ],
                      ),
                    );
                    if (replace == true) await sync.loadAccountVersion();
                  },
                  child: const Text('Load account version'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
