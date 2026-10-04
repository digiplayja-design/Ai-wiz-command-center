import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/app_studio/app_studio_client.dart';
import 'package:ai_wiz_command_center/app_studio/app_portal_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

const pid = '11111111-1111-4111-8111-111111111111';
final token = List.filled(43, 'a').join();
Map<String, dynamic> p({bool published = false, String role = 'owner'}) => {
  'id': pid,
  'project_id': pid,
  'name': 'Island Care',
  'description': 'Your requests, all in one place.',
  'accent': '#176BCA',
  'theme': 'light',
  'published': published,
  'version': 1,
  'project_version': 2,
  'payment_url': '',
  'role': role,
};
Map<String, dynamic> design() => {
  'id': pid,
  'name': 'Island Care',
  'version': 3,
  'spec': {'tagline': 'We care for your home.'},
  'brief': {},
};
Map<String, dynamic> clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));

class PortalsFake extends AppStudioClient {
  PortalsFake()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  Map<String, dynamic>? value;
  List<Map<String, dynamic>> members = [],
      invites = [],
      saved = [],
      invited = [];
  List<Map<String, dynamic>> rows = [];
  String? joined;
  int removed = 0, revoked = 0, launches = 0;
  bool failSave = false;
  Completer<Map<String, dynamic>>? wait;
  final List<VoidCallback> denied = [];
  @override
  void addAccessDeniedListener(VoidCallback listener) => denied.add(listener);
  @override
  void removeAccessDeniedListener(VoidCallback listener) =>
      denied.remove(listener);
  void deny() {
    for (final cb in denied.toList()) {
      cb();
    }
  }

  @override
  Future<Map<String, dynamic>> portalSetup(String projectId) async =>
      wait?.future ??
      {
        'portal': value == null ? null : clone(value!),
        'members': members,
        'invites': invites,
        'url': 'https://fixture.test/portals/$pid',
      };
  @override
  Future<Map<String, dynamic>> savePortal(
    String projectId,
    Map<String, dynamic> body,
  ) async {
    saved.add(clone(body));
    if (failSave) {
      throw const AppStudioException(
        'Refresh: another person changed this portal.',
        409,
      );
    }
    value = {...p(), ...body, 'id': pid, 'project_id': pid, 'version': 2};
    return {'portal': clone(value!)};
  }

  @override
  Future<Map<String, dynamic>> open(String id) async => {
    'project': design(),
    'versions': [],
    'previewHtml': null,
  };
  @override
  Future<List<Map<String, dynamic>>> portals() async => rows;
  @override
  Future<Map<String, dynamic>> portal(String id) async => {
    'portal': value ?? p(published: true, role: 'customer'),
    'url': 'https://fixture.test/portals/$pid',
  };
  @override
  Future<Map<String, dynamic>> invitePortal(
    String id,
    Map<String, dynamic> body,
  ) async {
    invited.add(clone(body));
    final invite = {
      'id': 'invite-1',
      ...body,
      'expires_at': '2099-01-01T00:00:00Z',
    };
    invites.add(invite);
    return {
      'invite': invite,
      'code': token,
      'join_url': 'https://app.test/app/?app_portal=$pid#invite=$token',
    };
  }

  @override
  Future<void> revokePortalInvite(String id, String inviteId) async {
    revoked++;
    invites = [];
  }

  @override
  Future<void> removePortalMember(String id, String memberId) async {
    removed++;
    members = [];
  }

  @override
  Future<Map<String, dynamic>> joinPortal(
    String code, {
    String? portalId,
  }) async {
    joined = code;
    return {'portal': p(published: true, role: 'customer')};
  }

  @override
  Future<Uri> launchPortal(String id) async {
    launches++;
    return Uri.parse('https://fixture.test/portals/$id#launch=$token');
  }
}

final boundary = GlobalKey();
Future<void> show(
  WidgetTester t,
  PortalsFake client, {
  bool manage = true,
  double width = 1100,
  double scale = 1,
  String theme = 'pure_white',
  String? invite,
  String? portalId,
  Future<void> Function(String)? copy,
  Future<bool> Function(Uri)? open,
}) async {
  t.view.physicalSize = Size(width, 1050);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme(theme),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundary,
        child: AppPortalScreen(
          client: client,
          project: manage ? design() : null,
          portalId: portalId,
          inviteToken: invite,
          copyText: copy,
          openUrl: open,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

String auth(String subject) =>
    'Bearer e.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': subject, 'session_id': 'session-$subject'}))).replaceAll('=', '')}.s';

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
  test('portal form rejects insecure or credential-bearing payment links', () {
    expect(validatePortalForm('A', '', ''), isNotNull);
    expect(
      validatePortalForm('Island Care', '', 'http://example.test'),
      isNotNull,
    );
    expect(
      validatePortalForm(
        'Island Care',
        '',
        'https://user:secret@example.test/pay',
      ),
      isNotNull,
    );
    expect(
      validatePortalForm(
        'Island Care',
        'Welcome',
        'https://pay.example.test/pay',
      ),
      isNull,
    );
  });
  test(
    'portal client preserves scope/version and validates success acknowledgements',
    () async {
      final calls = <http.Request>[];
      final client = AppStudioClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient((r) async {
          calls.add(r);
          if (r.method == 'DELETE') return http.Response('{}', 200);
          return http.Response(
            jsonEncode({'portal': p(), 'members': [], 'invites': []}),
            200,
          );
        }),
      );
      await client.savePortal(pid, {
        'version': 4,
        'project_version': 3,
        'published': true,
        'confirmed': true,
      });
      expect(calls.single.url.path, '/api/app-studio/projects/$pid/portal');
      expect(jsonDecode(calls.single.body)['version'], 4);
      await expectLater(
        client.revokePortalInvite(pid, 'invite-1'),
        throwsA(isA<AppStudioException>()),
      );
      await expectLater(
        client.removePortalMember(pid, 'user-1'),
        throwsA(isA<AppStudioException>()),
      );
      client.dispose();
    },
  );
  test(
    'invitation DTO accepts verified recipient links and rejects mismatched roles',
    () async {
      var role = 'staff';
      final client = AppStudioClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'invite': {
                'id': 'invite-1',
                'email': 'staff@example.test',
                'role': role,
              },
              'code': token,
              'join_url': 'https://app.test/app/?app_portal=$pid#invite=$token',
            }),
            201,
          ),
        ),
      );
      final result = await client.invitePortal(pid, {
        'email': 'staff@example.test',
        'role': 'staff',
      });
      expect(result['code'], token);
      role = 'customer';
      await expectLater(
        client.invitePortal(pid, {
          'email': 'staff@example.test',
          'role': 'staff',
        }),
        throwsA(isA<AppStudioException>()),
      );
      client.dispose();
    },
  );
  test(
    'launch accepts only short-lived fragment links on expected portal origin/path',
    () async {
      var address = 'https://fixture.test/portals/$pid#launch=$token';
      final client = AppStudioClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient(
          (_) async => http.Response(jsonEncode({'launch_url': address}), 200),
        ),
      );
      expect((await client.launchPortal(pid)).fragment, 'launch=$token');
      for (final unsafe in [
        'https://evil.test/portals/$pid#launch=$token',
        'https://fixture.test/portals/$pid/evil#launch=$token',
        'https://fixture.test/portals/$pid?launch=$token',
        'https://fixture.test/portals/$pid#launch=short',
        'https://user:password@fixture.test/portals/$pid#launch=$token',
      ]) {
        address = unsafe;
        await expectLater(
          client.launchPortal(pid),
          throwsA(isA<AppStudioException>()),
        );
      }
      client.dispose();
    },
  );
  test(
    'account change rejects an in-flight portal response and notifies all listeners',
    () async {
      final response = Completer<http.Response>(), sessions = ChangeNotifier();
      var subject = 'first';
      var notices = 0;
      final client = AppStudioClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': auth(subject)},
        sessionChanges: sessions,
        client: MockClient((_) => response.future),
      );
      client.onAccessDenied = () => notices++;
      client.addAccessDeniedListener(() => notices++);
      final request = client.portal(pid);
      final assertion = expectLater(
        request,
        throwsA(isA<AppStudioException>()),
      );
      subject = 'second';
      sessions.notifyListeners();
      response.complete(http.Response(jsonEncode({'portal': p()}), 200));
      await assertion;
      expect(notices, 2);
      client.dispose();
      sessions.dispose();
    },
  );
  testWidgets(
    'new portal is a draft with honest feature preflight and no publish on load',
    (t) async {
      final client = PortalsFake();
      await show(t, client);
      expect(find.text('Draft · access off'), findsOneWidget);
      expect(
        find.textContaining('Prototype screens and sample records'),
        findsOneWidget,
      );
      expect(client.saved, isEmpty);
      await tap(t, find.text('Publish portal'));
      expect(find.text('Publish this customer portal?'), findsOneWidget);
      await tap(t, find.text('Cancel'));
      expect(client.saved, isEmpty);
      await close(t);
    },
  );
  testWidgets(
    'publishing sends saved source revision only after explicit confirmation',
    (t) async {
      final client = PortalsFake();
      await show(t, client);
      await tap(t, find.text('Publish portal'));
      await tap(
        t,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Publish portal'),
        ),
      );
      expect(client.saved.single['project_version'], 3);
      expect(client.saved.single['published'], true);
      expect(client.saved.single['confirmed'], true);
      expect(find.text('Live portal'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'save conflict keeps form values and does not claim publish success',
    (t) async {
      final client = PortalsFake()..failSave = true;
      await show(t, client);
      await t.enterText(field('Portal name'), 'New company name');
      await tap(t, find.text('Save draft'));
      expect(find.text('New company name'), findsOneWidget);
      expect(find.textContaining('another person changed'), findsOneWidget);
      expect(
        find.textContaining('Your customer portal is live.'),
        findsNothing,
      );
      await close(t);
    },
  );
  testWidgets('refresh preserves unsaved setup when discard is declined', (
    t,
  ) async {
    final client = PortalsFake();
    await show(t, client);
    await t.enterText(field('Portal name'), 'Unsaved company');
    await tap(t, find.byTooltip('Refresh portals'));
    expect(find.text('Refresh portal?'), findsOneWidget);
    await tap(t, find.text('Cancel'));
    expect(find.text('Unsaved company'), findsOneWidget);
    expect(client.saved, isEmpty);
    await close(t);
  });
  testWidgets('public sharing never copies the secure session launch link', (
    t,
  ) async {
    final client = PortalsFake()..value = p(published: true);
    String? copied;
    Uri? opened;
    await show(
      t,
      client,
      copy: (value) async {
        copied = value;
      },
      open: (uri) async {
        opened = uri;
        return true;
      },
    );
    await tap(t, find.text('Copy public link'));
    expect(copied, 'https://fixture.test/portals/$pid');
    expect(client.launches, 0);
    await tap(t, find.text('Open portal'));
    expect(opened!.fragment, 'launch=$token');
    expect(copied!.contains(token), false);
    await close(t);
  });
  testWidgets(
    'unpublish explains access loss and cancellation makes no change',
    (t) async {
      final client = PortalsFake()..value = p(published: true);
      await show(t, client);
      await tap(t, find.text('Unpublish portal'));
      expect(find.textContaining('lose portal access'), findsOneWidget);
      await tap(t, find.text('Cancel'));
      expect(client.saved, isEmpty);
      await close(t);
    },
  );
  testWidgets(
    'invitation shows role scope and creates shareable code without email send',
    (t) async {
      final client = PortalsFake()..value = p(published: true);
      String? copied;
      await show(
        t,
        client,
        copy: (value) async {
          copied = value;
        },
      );
      await tap(t, find.text('People & invitations'));
      await t.enterText(field('Their KORLIX email'), 'Staff@Example.test');
      await tap(t, find.widgetWithText(ChoiceChip, 'Staff'));
      await tap(t, find.text('Create invitation'));
      expect(
        find.textContaining('Staff can view all portal requests'),
        findsOneWidget,
      );
      await tap(
        t,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Create invitation'),
        ),
      );
      expect(client.invited.single['email'], 'staff@example.test');
      expect(client.invited.single['role'], 'staff');
      await tap(t, find.text('Copy invitation link'));
      expect(copied, contains('#invite=$token'));
      expect(
        find.textContaining('No email is sent automatically'),
        findsOneWidget,
      );
      await close(t);
    },
  );
  testWidgets(
    'email/code setup cleared on session change, including pending response',
    (t) async {
      final client = PortalsFake()..value = p(published: true);
      await show(t, client);
      await tap(t, find.text('People & invitations'));
      await t.enterText(field('Their KORLIX email'), 'private@example.test');
      client.deny();
      await t.pumpAndSettle();
      expect(find.textContaining('Your sign-in changed'), findsOneWidget);
      expect(find.text('private@example.test'), findsNothing);
      expect(find.text('Island Care'), findsNothing);
      await close(t);
    },
  );
  testWidgets('invitation landing never joins until the user accepts', (
    t,
  ) async {
    final client = PortalsFake();
    await show(t, client, manage: false, portalId: pid, invite: token);
    expect(client.joined, isNull);
    await tap(t, find.text('Accept invitation'));
    expect(client.joined, token);
    expect(find.text('Open secure portal'), findsOneWidget);
    expect(find.text('Accept invitation'), findsNothing);
    await close(t);
  });
  testWidgets('owner can manage a portal then return to the directory', (
    t,
  ) async {
    final client = PortalsFake()
      ..value = p(published: true)
      ..rows = [p(published: true)];
    await show(t, client, manage: false);
    await tap(t, find.text('Manage portal'));
    expect(find.text('Setup & publish'), findsOneWidget);
    await tap(t, find.byTooltip('Back'));
    expect(find.text('Your customer portals'), findsOneWidget);
    expect(find.text('Manage portal'), findsOneWidget);
    await close(t);
  });
  testWidgets('directory explains empty state and offers joining', (t) async {
    final client = PortalsFake();
    await show(t, client, manage: false);
    expect(find.textContaining('No portals yet.'), findsOneWidget);
    expect(find.text('Accept invitation'), findsOneWidget);
    await close(t);
  });
  for (final theme in ['pure_white', 'midnight_black']) {
    testWidgets(
      'portal setup and people remain scrollable at 320px and 200% text $theme',
      (t) async {
        final client = PortalsFake()..value = p(published: true);
        await show(t, client, width: 320, scale: 2, theme: theme);
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Unpublish portal'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await tap(t, find.text('People & invitations'));
        await t.ensureVisible(find.text('No invitations yet.'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await close(t);
      },
    );
  }
  testWidgets('visual QA renders phone and desktop portal setup', (t) async {
    for (final width in [390.0, 1100.0]) {
      await show(t, PortalsFake()..value = p(published: true), width: width);
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/app-portal-${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(t.takeException(), isNull);
      await close(t);
    }
  });
}
