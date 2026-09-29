import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_invite_contacts.dart';
import 'package:ai_wiz_command_center/social/social_invite_io.dart';
import 'package:ai_wiz_command_center/social/social_invite_screen.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

class InviteIo extends SocialInviteIo {
  bool picker = false, draftResult = true;
  int picks = 0, imports = 0;
  ShareResultStatus shareResult = ShareResultStatus.success;
  final drafts = <Uri>[], copies = <String>[], shares = <String>[];
  Completer<List<InviteContact>>? pending;
  final people = [
    InviteContact(
      name: 'Jordan Rivera',
      emails: ['jordan@example.test'],
      phones: ['+1 (555) 123-4567'],
    ),
  ];
  @override
  bool get canPickContacts => picker;
  @override
  Future<List<InviteContact>> chooseContacts() {
    picks++;
    return pending?.future ?? Future.value(people);
  }

  @override
  Future<InviteImport?> importContacts() async {
    imports++;
    return InviteImport(people, 0, 0);
  }

  @override
  Future<void> copy(String text) async {
    copies.add(text);
  }

  @override
  Future<ShareResultStatus> share(String text, Rect origin) async {
    expect(origin.width, greaterThan(0));
    shares.add(text);
    return shareResult;
  }

  @override
  Future<bool> openDraft(Uri uri) async {
    drafts.add(uri);
    return draftResult;
  }
}

InviteImport parse(String text, [String name = 'contacts.csv']) =>
    importInviteContacts(name, Uint8List.fromList(utf8.encode(text)));

Future<void> reveal(WidgetTester t, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    final scroll = t
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    scroll.jumpTo(0);
    await t.pumpAndSettle();
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      scroll.jumpTo((scroll.pixels + 240).clamp(0, scroll.maxScrollExtent));
      await t.pumpAndSettle();
    }
  }
  await Scrollable.ensureVisible(t.element(finder), alignment: .5);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await reveal(t, finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  test('CSV handles quoted names, export headers, duplicates and invalid rows', () {
    final imported = parse(
      '\uFEFFName,E-mail 1 - Value,Phone 1 - Value\r\n"Rivera, Jordan",jordan@example.test,+1 (555) 123-4567\r\nJordan,jordan@example.test,+1 555 987 6543\r\nInvalid,no email,abc\r\n',
    );
    expect(imported.contacts.single.name, 'Rivera, Jordan');
    expect(imported.contacts.single.phones, ['+15551234567', '+15559876543']);
    expect(imported.duplicates, 1);
    expect(imported.skipped, 1);
    expect(
      parse(
        'First Name,Last Name,E-mail Address,Mobile Phone\nSam,Lee,sam@example.test,+44 7700 900123',
      ).contacts.single.name,
      'Sam Lee',
    );
  });
  test('vCard imports folded Unicode names and multiple email/phone fields', () {
    final person = parse(
      'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Zoë \\nRivera\\,\r\n  Jordan\r\nEMAIL;TYPE=HOME:zoe@example.test\r\nitem1.EMAIL:work@example.test\r\nTEL;TYPE=CELL:tel:+1-555-123-4567\r\nEND:VCARD',
      'family.vcf',
    ).contacts.single;
    expect(person.name, contains('Zoë'));
    expect(person.name, contains('Rivera, Jordan'));
    expect(person.emails, ['zoe@example.test', 'work@example.test']);
    expect(person.phones, ['+15551234567']);
  });
  test(
    'bad files, invalid encoding, oversized imports and malformed cards fail clearly',
    () {
      for (final bad in [
        'Name,Email\n"unfinished,sam@example.test',
        'Name,Email\nNobody,no-email',
        'Just names\nSam',
      ]) {
        expect(() => parse(bad), throwsA(isA<SocialException>()));
      }
      expect(
        () => parse('BEGIN:VCARD\nEMAIL:x@example.test', 'x.vcf'),
        throwsA(isA<SocialException>()),
      );
      expect(
        () => importInviteContacts('x.csv', Uint8List.fromList([255])),
        throwsA(isA<SocialException>()),
      );
      expect(
        () => importInviteContacts('x.csv', Uint8List(2 * 1024 * 1024 + 1)),
        throwsA(isA<SocialException>()),
      );
      expect(
        () => parse(
          'Name,Email\n${List.generate(501, (i) => 'Person $i,p$i@example.test').join('\n')}',
        ),
        throwsA(isA<SocialException>()),
      );
    },
  );
  test(
    'draft URI targets one validated recipient and preserves message characters',
    () {
      const body = 'Join me 🎉\nFriends & family? 100% yes + more';
      final uri = inviteDraftUri(
        recipient: 'friend@example.test',
        email: true,
        message: body,
      );
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'friend@example.test');
      expect(uri.queryParameters['body'], body);
      expect(uri.queryParameters.keys, ['subject', 'body']);
      final sms = inviteDraftUri(
        recipient: '+1 (555) 123-4567',
        email: false,
        message: body,
      );
      expect(sms.path, '+15551234567');
      expect(sms.queryParameters['body'], body);
      for (final bad in [
        'a@example.test,b@example.test',
        'a@example.test\r\nBcc:b@example.test',
      ]) {
        expect(
          () => inviteDraftUri(recipient: bad, email: true, message: body),
          throwsA(isA<SocialException>()),
        );
      }
      expect(invitePhone('+15551234567;5557654321'), isNull);
    },
  );
  testWidgets('Social has a prominent invite route', (t) async {
    final store = social.Store();
    await social.mount(t, SocialScreen(client: store.client));
    await tap(t, find.byTooltip('Invite friends & family'));
    expect(find.byType(SocialInviteScreen), findsOneWidget);
    expect(find.text('Better with\nyour people.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'import and review never send; only explicit draft action opens chosen recipient',
    (t) async {
      final store = social.Store(), io = InviteIo();
      await social.mount(
        t,
        SocialInviteScreen(client: store.client, handle: 'alex', io: io),
      );
      expect(io.imports + io.picks, 0);
      expect(io.drafts, isEmpty);
      await tap(t, find.text('Import contacts'));
      expect(io.imports, 1);
      await tap(t, find.text('Review invitation'));
      expect(io.drafts, isEmpty);
      expect(find.text('To: Jordan Rivera'), findsOneWidget);
      await tap(t, find.text('Open email draft'));
      expect(io.drafts.single.path, 'jordan@example.test');
      expect(io.drafts.single.queryParameters['body'], contains('@alex'));
      await tap(t, find.text('+15551234567'));
      await tap(t, find.text('Open text draft'));
      expect(io.drafts.last.scheme, 'sms');
      expect(io.drafts.last.path, '+15551234567');
      await tap(t, find.text('Close'));
      expect(
        find.text('Draft opened · delivery not confirmed'),
        findsOneWidget,
      );
      expect(store.calls, isEmpty, reason: 'Contacts never reach a backend');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'share and copy include handle, with fallback when sharing unavailable',
    (t) async {
      final store = social.Store(),
          io = InviteIo()..shareResult = ShareResultStatus.unavailable;
      await social.mount(
        t,
        SocialInviteScreen(client: store.client, handle: 'alex', io: io),
      );
      await tap(t, find.text('Share invitation'));
      expect(io.shares.single, socialInvitation('alex'));
      await tap(t, find.text('Copy invitation'));
      expect(io.copies.single, contains(socialInviteUrl));
      await tap(t, find.byTooltip('Copy join link'));
      expect(io.copies.last, socialInviteUrl);
      expect(io.drafts, isEmpty);
      expect(store.calls, isEmpty);
    },
  );
  testWidgets('late device contacts are discarded after account switch', (
    t,
  ) async {
    final store = social.Store(),
        io = InviteIo()
          ..picker = true
          ..pending = Completer<List<InviteContact>>();
    await social.mount(
      t,
      SocialInviteScreen(client: store.client, handle: 'alex', io: io),
    );
    // A pending picker keeps a progress indicator active, so do not settle.
    await reveal(t, find.text('Choose contacts'));
    await t.tap(find.text('Choose contacts'));
    await t.pump();
    expect(io.picks, 1);
    store.token = 'Bearer account-two';
    store.revision.value++;
    io.pending!.complete(io.people);
    await t.pumpAndSettle();
    expect(find.textContaining('Your session changed.'), findsOneWidget);
    expect(find.text('Jordan Rivera'), findsNothing);
    expect(io.drafts, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('account switch clears open recipient review', (t) async {
    final store = social.Store(), io = InviteIo();
    await social.mount(
      t,
      SocialInviteScreen(client: store.client, handle: 'alex', io: io),
    );
    await tap(t, find.text('Import contacts'));
    await tap(t, find.text('Review invitation'));
    store.token = 'Bearer account-two';
    store.revision.value++;
    await t.pumpAndSettle();
    expect(find.text('Your session changed'), findsOneWidget);
    expect(find.text('To: Jordan Rivera'), findsNothing);
    expect(find.text('Open email draft'), findsNothing);
    expect(io.drafts, isEmpty);
    expect(t.takeException(), isNull);
  });
  for (final v in [
    (320.0, 1.4, 'pure_black'),
    (390.0, 1.0, 'korlix_blue'),
    (390.0, 1.0, 'pure_white'),
    (1280.0, 1.0, 'pure_black'),
  ]) {
    testWidgets('invites fit ${v.$1}px ${v.$2}x ${v.$3}', (t) async {
      final store = social.Store(), io = InviteIo();
      await social.mount(
        t,
        SocialInviteScreen(client: store.client, handle: 'alex', io: io),
        width: v.$1,
        scale: v.$2,
        theme: v.$3,
      );
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-invite-${v.$1}-${v.$3}');
      await tap(t, find.text('Import contacts'));
      await tap(t, find.text('Review invitation'));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-invite-review-${v.$1}-${v.$3}');
      await tap(t, find.text('Close'));
      await tap(t, find.text('Add a person'));
      expect(t.takeException(), isNull);
      await tap(t, find.text('Cancel'));
    });
  }
}
