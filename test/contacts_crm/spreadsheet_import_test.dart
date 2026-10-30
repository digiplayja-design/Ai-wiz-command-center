import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/contacts_crm/contact_import.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_client.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_screen.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_style.dart';
import 'contacts_screen_test.dart' as fixtures;

class SpreadsheetPicker extends FilePicker {
  PlatformFile? file = PlatformFile(
    name: 'contacts.xlsx',
    size: 20,
    bytes: Uint8List.fromList(utf8.encode('workbook-fixture')),
  );
  Completer<FilePickerResult?>? pending;
  int picks = 0;
  String? savedName, savedText;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    picks++;
    expect(withData, true);
    expect(allowedExtensions, containsAll(['csv', 'tsv', 'xlsx']));
    return pending?.future ?? (file == null ? null : FilePickerResult([file!]));
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedName = fileName;
    savedText = utf8.decode(bytes!);
    return '/test/$fileName';
  }
}

Map<String, dynamic> preview({
  String worksheet = 'Customers',
  bool needsMapping = false,
}) => {
  'contacts': needsMapping ? [] : [fixtures.sample, fixtures.fixtures[1]],
  'duplicates': 1,
  'errors': [
    {'row': 7, 'message': 'Enter a valid email address.'},
  ],
  'total': 4,
  'spreadsheet': {
    'sheets': ['Customers', 'Vendors'],
    'worksheet': worksheet,
    'headerRow': 1,
    'columns': [
      {'index': 0, 'label': 'Name', 'sample': 'Jordan Lee'},
      {'index': 1, 'label': 'Email', 'sample': 'jordan@example.com'},
    ],
    'headerRows': [
      {'row': 1, 'label': 'Name · Email'},
      {'row': 2, 'label': 'Jordan Lee · jordan@example.com'},
    ],
    'mapping': {
      'name': needsMapping ? null : 0,
      'email': needsMapping ? null : 1,
    },
    'defaultCategory': 'unknown',
    'needsMapping': needsMapping,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FilePicker.platform = SpreadsheetPicker();
  late SpreadsheetPicker picker;
  setUp(() {
    final old = FilePicker.platform;
    picker = SpreadsheetPicker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = old);
  });
  Future<void> open(
    WidgetTester tester,
    FutureOr<http.Response> Function(http.Request) handle, {
    double width = 1024,
    double textScale = 1,
  }) async {
    fixtures.viewport(tester, width, height: 900);
    final client = fixtures.api(handle);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: CrmStyle.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: ContactImport(client: client)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> upload(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Choose file'));
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'spreadsheet upload previews and imports only selected rows; new contacts are visible despite prior filters',
    (tester) async {
      Map<String, dynamic>? saved, lastQuery;
      var imported = false;
      fixtures.viewport(tester, 390, height: 1100);
      await tester.pumpWidget(
        MaterialApp(
          home: ContactsScreen(
            client: fixtures.api((request) {
              if (request.url.path.endsWith('/imports/preview')) {
                expect(jsonDecode(request.body)['filename'], 'contacts.xlsx');
                return fixtures.result(preview());
              }
              if (request.url.path.endsWith('/imports')) {
                saved = jsonDecode(request.body);
                imported = true;
                return fixtures.result({'imported': 1, 'duplicates': 0});
              }
              if (imported && request.url.path == '/api/contacts') {
                lastQuery = request.url.queryParameters;
              }
              return fixtures.normal(request);
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Upload spreadsheet'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Existing filter');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-contacts')));
      await tester.pumpAndSettle();
      await upload(tester);
      await tester.ensureVisible(
        find.widgetWithText(CheckboxListTile, 'Alex Rivera'),
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alex Rivera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 1 contacts'));
      await tester.pumpAndSettle();
      expect(saved?['confirmed'], true);
      expect((saved?['contacts'] as List).length, 1);
      expect(saved?['contacts'][0]['name'], 'Jordan Lee');
      expect(lastQuery?['q'], '');
      expect(lastQuery?['category'], '');
      expect(lastQuery?['offset'], '0');
      expect(lastQuery?['sort'], 'updated_at');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'worksheet selection reparses the chosen worksheet before saving',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      await open(tester, (request) {
        final b = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(b);
        return fixtures.result(
          preview(worksheet: b['worksheet'] ?? 'Customers'),
        );
      });
      await upload(tester);
      await tester.tap(find.text('Customers').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vendors').last);
      await tester.pumpAndSettle();
      expect(bodies.last['worksheet'], 'Vendors');
      expect(bodies.last.containsKey('mapping'), false);
      expect(find.text('2 ready'), findsOneWidget);
    },
  );

  testWidgets(
    'column changes disable import until successful refreshed preview',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      var failRefresh = true;
      await open(tester, (request) {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (bodies.length > 1 && failRefresh) {
          return fixtures.result({'error': 'Connection unavailable'}, 503);
        }
        return fixtures.result(preview());
      });
      await upload(tester);
      await reveal(tester, 'Match spreadsheet columns');
      final category = find.byKey(const ValueKey('default-category-1'));
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lead').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Import 2 contacts'),
            )
            .onPressed,
        isNull,
      );
      await reveal(tester, 'Update preview');
      expect(bodies.last['defaultCategory'], 'lead');
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Import 2 contacts'),
            )
            .onPressed,
        isNull,
      );
      failRefresh = false;
      await reveal(tester, 'Update preview');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Import 2 contacts'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'downloadable template and error report contain useful columns and actual row numbers',
    (tester) async {
      await open(tester, (_) => fixtures.result(preview()));
      await reveal(tester, 'Download CSV template');
      expect(picker.savedName, 'Korlix-CRM-contacts-template.csv');
      expect(picker.savedText, contains('Follow Up On'));
      await upload(tester);
      await reveal(tester, 'Rows to fix');
      await reveal(tester, 'Download all row issues');
      expect(picker.savedText, contains('7,"Enter a valid email address."'));
    },
  );

  testWidgets(
    'file picker is single-flight, cancellation recovers, and oversized files never upload',
    (tester) async {
      int requests = 0;
      await open(tester, (_) {
        requests++;
        return fixtures.result(preview());
      });
      picker.pending = Completer();
      await tester.ensureVisible(find.text('Choose file'));
      await tester.tap(find.text('Choose file'));
      await tester.pump();
      await tester.tap(find.text('Choose file'));
      expect(picker.picks, 1);
      picker.pending!.complete(null);
      await tester.pumpAndSettle();
      picker.pending = null;
      picker.file = PlatformFile(
        name: 'too-big.csv',
        size: 3 * 1024 * 1024,
        bytes: Uint8List(1),
      );
      await upload(tester);
      expect(requests, 0);
      expect(find.text('Choose a file smaller than 2 MB.'), findsOneWidget);
    },
  );

  testWidgets('unexpected save response does not report a successful import', (
    tester,
  ) async {
    await open(
      tester,
      (request) => fixtures.result(
        request.url.path.endsWith('/preview') ? preview() : {'ok': true},
      ),
    );
    await upload(tester);
    await tester.tap(find.text('Import 2 contacts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('did not confirm the import'), findsOneWidget);
  });

  testWidgets('mapping and review fit small screens with larger text', (
    tester,
  ) async {
    await open(
      tester,
      (_) => fixtures.result(preview(needsMapping: true)),
      width: 320,
      textScale: 1.3,
    );
    await upload(tester);
    expect(tester.takeException(), isNull);
    await reveal(tester, 'Update preview');
    expect(tester.takeException(), isNull);
  });

  testWidgets('account change while file picker is open prevents upload', (
    tester,
  ) async {
    String token(String user) =>
        'x.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'test', 'sub': user, 'session_id': 'session'})))}.x';
    String identity = token('one');
    final revision = ValueNotifier(0);
    int requests = 0;
    final client = ContactsClient(
      backendBaseUrl: 'https://test.invalid',
      headersBuilder: () => {'Authorization': 'Bearer $identity'},
      sessionChanges: revision,
      client: MockClient((_) async {
        requests++;
        return fixtures.result(preview());
      }),
    );
    addTearDown(() {
      client.dispose();
      revision.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ContactImport(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    picker.pending = Completer();
    await tester.ensureVisible(find.text('Choose file'));
    await tester.tap(find.text('Choose file'));
    await tester.pump();
    identity = token('two');
    revision.value++;
    picker.pending!.complete(FilePickerResult([picker.file!]));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('Sign in again and reopen CRM.'), findsOneWidget);
  });
}
