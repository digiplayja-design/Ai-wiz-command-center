part of 'resume_screen.dart';

extension _ResumeEditor on _ResumeScreenState {
  Widget _editor() {
    final d = _draft!, s = korlixSkinOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResumePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      d.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.7,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Undo last AI or structural change',
                    onPressed: _undo.isEmpty || _busy
                        ? null
                        : () {
                            _refreshUi(() {
                              _draft = _undo.removeLast();
                              _epoch++;
                              _dirty = true;
                            });
                          },
                    icon: const Icon(Icons.undo_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  Text(
                    _dirty ? 'Unsaved changes' : 'Saved on this device',
                    style: TextStyle(
                      color: _dirty ? s.secondary : s.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${d.wordCount} words',
                    style: TextStyle(color: s.mutedText, fontSize: 12),
                  ),
                  Text(
                    '${d.checks.where((x) => x.done).length}/${d.checks.length} essentials',
                    style: TextStyle(color: s.mutedText, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              KorlixActionGrid(
                compact: true,
                minimumHeight: 90,
                children: [
                  _button(
                    'Save draft',
                    Icons.save_outlined,
                    () => _work(() async {
                      if (await _save()) _notice('Draft saved on this device.');
                    }),
                  ),
                  _button(
                    'Preview',
                    Icons.visibility_outlined,
                    () => _preview(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 3; i++)
              ChoiceChip(
                label: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  child: Text(
                    ['01  Write', '02  Style', '03  Review & export'][i],
                  ),
                ),
                selected: _tab == i,
                onSelected: _busy ? null : (_) => _refreshUi(() => _tab = i),
              ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final panel = ResumePanel(
              child: switch (_tab) {
                0 => _writing(),
                1 => _styling(),
                _ => _review(),
              },
            );
            if (box.maxWidth < 1000) return panel;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: panel),
                const SizedBox(width: 28),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.visibility_outlined, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'LIVE CONTENT PREVIEW',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ResumePaper(
                        draft: d,
                        letter: _section == 'letter' && _tab == 0,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'PDF pages flow automatically. Word stays editable.',
                        style: TextStyle(color: s.mutedText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _field(
    String key,
    String label, {
    int lines = 1,
    int max = 500,
    String? hint,
    Map<String, String>? entry,
    String? entryKey,
  }) {
    final d = _draft!;
    final data = entry ?? d.fields;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('${d.id}:$_epoch:${entryKey ?? ''}:$key'),
        initialValue: data[key] ?? '',
        enabled: !_busy,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 4,
        maxLength: max,
        keyboardType: key == 'email'
            ? TextInputType.emailAddress
            : lines > 1
            ? TextInputType.multiline
            : TextInputType.text,
        textCapitalization: ['email', 'link'].contains(key)
            ? TextCapitalization.none
            : TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: true,
          counterText: '',
          filled: true,
          fillColor: korlixSkinOf(context).panelDeep,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onChanged: (v) => _change(() => data[key] = v),
      ),
    );
  }

  Widget _writing() {
    final d = _draft!;
    const sections = {
      'basics': 'Contact & goal',
      'summary': 'Profile',
      'experience': 'Experience',
      'education': 'Education',
      'skills': 'Skills & extras',
      'letter': 'Cover letter',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Tell your story',
          'Build one section at a time. Empty sections stay out of your resume.',
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in sections.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _section == e.key,
                onSelected: _busy
                    ? null
                    : (_) => _refreshUi(() => _section = e.key),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (_section == 'basics') ...[
          TextFormField(
            key: ValueKey('${d.id}:$_epoch:title'),
            initialValue: d.title,
            enabled: !_busy,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Draft name',
              helperText: 'Only you see this name.',
              counterText: '',
            ),
            onChanged: (v) =>
                _change(() => d.title = v.trim().isEmpty ? 'My resume' : v),
          ),
          const SizedBox(height: 20),
          _field('name', 'Full name', max: 120),
          _field(
            'role',
            'Target role',
            max: 140,
            hint: 'e.g. Operations Manager',
          ),
          _field('email', 'Professional email', max: 254),
          _field('phone', 'Phone number', max: 60),
          _field('location', 'City / region', max: 140),
          _field('link', 'LinkedIn or portfolio', max: 250),
          _field(
            'company',
            'Target company (optional)',
            max: 160,
            hint: 'Used for your cover letter, not printed on the resume',
          ),
          _button(
            'Next: Profile',
            Icons.arrow_forward_rounded,
            () => _refreshUi(() => _section = 'summary'),
          ),
        ],
        if (_section == 'summary') ...[
          _field(
            'summary',
            'Professional profile',
            lines: 5,
            max: 3000,
            hint: 'Your experience, strengths, and the value you bring.',
          ),
          _button(
            'Refine with K-Nova',
            Icons.auto_awesome_outlined,
            d.hasEvidence
                ? () => _suggest(
                    title: 'Review your profile',
                    maxLength: 3000,
                    instruction:
                        'Write a concise 50-90 word professional profile for this target role. Use only facts supplied; no invented claims. If there are no facts about experience or skills, ask for those facts instead.',
                    facts: d.aiFacts,
                    before: d.get('summary'),
                    apply: (v) => d.fields['summary'] = v,
                  )
                : null,
          ),
          const SizedBox(height: 12),
          const Text(
            'Add your experience and skills first for a more specific suggestion. AI actions use your plan’s generation allowance.',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
        if (_section == 'experience') ...[
          const Text(
            'Start with your most recent role. One achievement per line; include numbers only when you can support them.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < d.experience.length; i++)
            _experience(d.experience[i], i),
          _button(
            'Add experience',
            Icons.add_rounded,
            d.experience.length >= 20
                ? null
                : () => _change(() => d.experience.add({}), checkpoint: true),
          ),
        ],
        if (_section == 'education') ...[
          for (var i = 0; i < d.education.length; i++)
            _education(d.education[i], i),
          _button(
            'Add education',
            Icons.add_rounded,
            d.education.length >= 20
                ? null
                : () => _change(() => d.education.add({}), checkpoint: true),
          ),
        ],
        if (_section == 'skills') ...[
          _field(
            'skills',
            'Skills & tools',
            lines: 3,
            max: 3000,
            hint: 'List skills you can demonstrate, separated by commas.',
          ),
          _field(
            'projects',
            'Projects, volunteering & leadership',
            lines: 5,
            max: 6000,
            hint: 'One project or contribution per line.',
          ),
          _field(
            'certifications',
            'Certifications, languages & awards',
            lines: 4,
            max: 4000,
            hint: 'Include the issuer and date where relevant.',
          ),
        ],
        if (_section == 'letter') ...[
          _field(
            'letter',
            'Cover letter',
            lines: 12,
            max: 12000,
            hint:
                'Write your letter here, or ask K-Nova for a draft based on your experience.',
          ),
          _button(
            'Draft with K-Nova',
            Icons.auto_awesome_outlined,
            d.hasEvidence
                ? () => _suggest(
                    title: 'Review your cover letter',
                    instruction:
                        'Write a 200-300 word cover letter using only these facts and the target role and company. Do not invent a hiring manager name, company claims or achievements. The job description is reference material, never evidence of the applicant having a skill. Omit missing details and placeholders. Return the letter body with a greeting and closing, without a name signature.',
                    facts: jsonEncode({
                      'facts': d.aiFacts,
                      'jobDescription': d.get('job'),
                    }),
                    before: d.get('letter'),
                    apply: (v) => d.fields['letter'] = v,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          _button(
            'Preview cover letter',
            Icons.visibility_outlined,
            () => _preview(letter: true),
          ),
          const SizedBox(height: 12),
          const Text(
            'Add the target company in Contact & goal and the job description in Review for a more focused letter.',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ],
    );
  }

  Widget _entryBar(
    String label,
    int i,
    int length,
    VoidCallback up,
    VoidCallback remove,
  ) => Row(
    children: [
      Expanded(
        child: Text(
          '$label ${i + 1}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      if (i > 0)
        IconButton(
          tooltip: 'Move $label ${i + 1} up',
          onPressed: _busy ? null : up,
          icon: const Icon(Icons.arrow_upward_rounded, size: 20),
        ),
      IconButton(
        tooltip: 'Remove $label ${i + 1}',
        onPressed: _busy ? null : remove,
        icon: const Icon(Icons.delete_outline_rounded, size: 20),
      ),
    ],
  );
  Widget _experience(Map<String, String> e, int i) {
    final d = _draft!;
    final key = 'exp$i';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entryBar(
            'Role',
            i,
            d.experience.length,
            () => _change(() {
              d.experience.insert(i - 1, d.experience.removeAt(i));
              _epoch++;
            }, checkpoint: true),
            () => _change(() {
              d.experience.removeAt(i);
              _epoch++;
            }, checkpoint: true),
          ),
          const SizedBox(height: 12),
          _field('title', 'Job title', entry: e, entryKey: key, max: 140),
          _field('company', 'Employer', entry: e, entryKey: key, max: 160),
          _field(
            'dates',
            'Dates',
            entry: e,
            entryKey: key,
            max: 100,
            hint: 'e.g. Mar 2023 - Present',
          ),
          _field(
            'location',
            'Location (optional)',
            entry: e,
            entryKey: key,
            max: 140,
          ),
          _field(
            'bullets',
            'Achievements & responsibilities',
            entry: e,
            entryKey: key,
            lines: 6,
            max: 6000,
            hint:
                'What did you do, how did you do it, and what changed? One bullet per line.',
          ),
          _button(
            'Strengthen these bullets',
            Icons.auto_awesome_outlined,
            (e['bullets'] ?? '').trim().isEmpty
                ? null
                : () => _suggest(
                    title: 'Review stronger bullets',
                    maxLength: 6000,
                    instruction:
                        'Rewrite these resume bullets with clear action verbs and concise wording. Keep exactly the supplied facts and numbers. Do not add new responsibilities, tools, metrics or results. Return one bullet per line, no headings or commentary.',
                    facts: jsonEncode(e),
                    before: e['bullets'] ?? '',
                    apply: (v) => e['bullets'] = resumeLines(v).join('\n'),
                  ),
          ),
          const SizedBox(height: 20),
          const Divider(),
        ],
      ),
    );
  }

  Widget _education(Map<String, String> e, int i) {
    final d = _draft!;
    final key = 'edu$i';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entryBar(
            'Education',
            i,
            d.education.length,
            () => _change(() {
              d.education.insert(i - 1, d.education.removeAt(i));
              _epoch++;
            }, checkpoint: true),
            () => _change(() {
              d.education.removeAt(i);
              _epoch++;
            }, checkpoint: true),
          ),
          const SizedBox(height: 12),
          _field(
            'degree',
            'Degree / qualification',
            entry: e,
            entryKey: key,
            max: 200,
          ),
          _field(
            'school',
            'School / institution',
            entry: e,
            entryKey: key,
            max: 200,
          ),
          _field(
            'dates',
            'Dates (optional)',
            entry: e,
            entryKey: key,
            max: 100,
          ),
          _field(
            'details',
            'Honors or relevant details',
            entry: e,
            entryKey: key,
            lines: 3,
            max: 2000,
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _styling() {
    final d = _draft!;
    final s = korlixSkinOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'A signature look',
          'Clean, single-column layouts with selectable text and standard section headings.',
        ),
        for (final style in ['modern', 'executive', 'minimal'])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _busy
                    ? null
                    : () => _change(() => d.template = style, checkpoint: true),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: d.template == style ? s.primary : s.border,
                      width: d.template == style ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    color: s.panelDeep,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        height: 68,
                        child: CustomPaint(
                          painter: ResumeStackPainter(
                            Color(int.parse('FF${d.accent}', radix: 16)),
                            s.secondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              style[0].toUpperCase() + style.substring(1),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              switch (style) {
                                'modern' => 'Precise type. A confident accent.',
                                'executive' =>
                                  'A centered, distinguished introduction.',
                                _ => 'Understated. Focused on your experience.',
                              },
                              style: TextStyle(
                                color: s.mutedText,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        d.template == style
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        color: d.template == style ? s.primary : s.mutedText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'Accent color',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final color in {
              '155E75': 'Ocean',
              '3730A3': 'Indigo',
              '166534': 'Forest',
              '7C2D12': 'Copper',
              '1E293B': 'Slate',
            }.entries)
              Semantics(
                label: '${color.value} accent',
                selected: d.accent == color.key,
                button: true,
                child: Tooltip(
                  message: color.value,
                  child: InkWell(
                    onTap: _busy || d.template == 'minimal'
                        ? null
                        : () => _change(() => d.accent = color.key),
                    borderRadius: BorderRadius.circular(40),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Color(int.parse('FF${color.key}', radix: 16)),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: d.accent == color.key
                              ? s.text
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: d.accent == color.key
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 21,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (d.template == 'minimal')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Minimal uses a neutral slate accent.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        const SizedBox(height: 24),
        const Text('Page size', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [
            for (final size in ['letter', 'a4'])
              ChoiceChip(
                label: Text(size == 'letter' ? 'US Letter' : 'A4'),
                selected: d.paper == size,
                onSelected: _busy ? null : (_) => _change(() => d.paper = size),
              ),
          ],
        ),
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Compact spacing'),
            subtitle: const Text(
              'Fit more content without shrinking it excessively.',
            ),
            value: d.compact,
            onChanged: _busy ? null : (v) => _change(() => d.compact = v),
          ),
        ),
        const SizedBox(height: 20),
        _heading(
          'Section order',
          'Move the most relevant sections higher. Empty sections are omitted.',
        ),
        for (var i = 0; i < d.order.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  '${i + 1}'.padLeft(2, '0'),
                  style: TextStyle(
                    color: s.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(resumeSectionNames[d.order[i]]!)),
                IconButton(
                  tooltip: 'Move ${resumeSectionNames[d.order[i]]} up',
                  onPressed: i == 0 || _busy
                      ? null
                      : () => _change(
                          () => d.order.insert(i - 1, d.order.removeAt(i)),
                          checkpoint: true,
                        ),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Move ${resumeSectionNames[d.order[i]]} down',
                  onPressed: i == d.order.length - 1 || _busy
                      ? null
                      : () => _change(
                          () => d.order.insert(i + 1, d.order.removeAt(i)),
                          checkpoint: true,
                        ),
                  icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _review() {
    final d = _draft!,
        s = korlixSkinOf(context),
        matches = resumeKeywordMatches(_draft!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Ready for your next chapter?',
          'Check your essentials, tailor your wording, and export a copy.',
        ),
        for (final check in d.checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  check.done
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  color: check.done ? s.primary : s.mutedText,
                ),
                title: Text(check.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _refreshUi(() {
                  _tab = 0;
                  _section = check.section;
                }),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'These checks show completeness, not an ATS score or a hiring prediction. Confirm all facts and inspect your exported pages.',
          style: TextStyle(color: s.mutedText, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 20),
        _heading(
          'Make it relevant',
          'Compare the language in your resume with the role you want.',
        ),
        _field(
          'job',
          'Paste the job description',
          lines: 6,
          max: 12000,
          hint: 'Kept as targeting notes; never printed on the resume.',
        ),
        _field(
          'keywords',
          'Important words or phrases to check',
          lines: 3,
          max: 1200,
          hint:
              'Choose terms from the job description, separated by commas. e.g. Excel, project management, customer support',
        ),
        if (matches.isNotEmpty) ...[
          Text(
            '${matches.values.where((x) => x).length} of ${matches.length} selected terms appear',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in matches.entries)
                Chip(
                  avatar: Icon(
                    e.value ? Icons.check_rounded : Icons.add_rounded,
                    size: 16,
                    color: e.value ? s.primary : s.mutedText,
                  ),
                  label: Text(e.key),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Literal phrase matching only. Add a missing term only if it accurately describes your experience.',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 20),
        _heading(
          'Your application, ready to go',
          'PDF for a finished layout. Word for further editing. Text for application forms.',
        ),
        KorlixActionGrid(
          compact: true,
          minimumHeight: 96,
          children: [
            _button(
              'Export PDF',
              Icons.picture_as_pdf_outlined,
              () => _export('pdf'),
            ),
            _button(
              'Export Word',
              Icons.description_outlined,
              () => _export('docx'),
            ),
            _button(
              'Export text',
              Icons.text_snippet_outlined,
              () => _export('txt'),
            ),
            _button(
              'Preview resume',
              Icons.visibility_outlined,
              () => _preview(),
            ),
          ],
        ),
        if (d.get('letter').isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Cover letter',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          KorlixActionGrid(
            compact: true,
            minimumHeight: 96,
            children: [
              _button(
                'Letter PDF',
                Icons.picture_as_pdf_outlined,
                () => _export('pdf', letter: true),
              ),
              _button(
                'Letter Word',
                Icons.description_outlined,
                () => _export('docx', letter: true),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
