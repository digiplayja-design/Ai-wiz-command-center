import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_brain/brain_api.dart';
import 'package:korlix_brain/brain_auth.dart';
import 'package:korlix_brain/brain_directions.dart';
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String fixtureToken() {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg':'none'})}.${part({'sub':'directions-fixture','iss':'https://auth.example.test','exp':DateTime.now().add(const Duration(hours:1)).millisecondsSinceEpoch ~/ 1000})}.fixture';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('only exact confirmed destination and mode open on approved Maps origins', () {
    const destination = '1000 Fifth Avenue, New York, NY 10028 & Suite 2';
    for (final apple in [true, false]) {
      final uri = apple
          ? Uri.https('maps.apple.com', '/directions', {'destination':destination,'mode':'walking'})
          : Uri.https('www.google.com', '/maps/dir/', {'api':'1','destination':destination,'travelmode':'walking'});
      Uri? check(String value) => checkedBrainDirections(value,
          destination: destination, mode:'walking', apple:apple);
      expect(check(uri.toString()), uri);
      expect(check(uri.replace(host:'evil.example').toString()), isNull);
      expect(check(uri.replace(scheme:'http').toString()), isNull);
      expect(check(uri.replace(userInfo:'user:password').toString()), isNull);
      expect(check(uri.replace(fragment:'x').toString()), isNull);
      expect(check(uri.replace(port:444).toString()), isNull);
      expect(check(uri.replace(path:'/search').toString()), isNull);
      expect(check('${uri.toString()}&destination=another'), isNull);
      expect(check('${uri.toString()}&start=0'), isNull);
      expect(checkedBrainDirections(uri.toString(), destination:'Different place',
          mode:'walking', apple:apple), isNull);
    }
  });

  test('malformed encoded parameters and unsupported modes fail closed', () {
    expect(checkedBrainDirections(
      'https://www.google.com/maps/dir/?api=1&destination=%FF&travelmode=walking',
      destination:'A valid destination', mode:'walking', apple:false), isNull);
    expect(checkedBrainDirections(
      'https://www.google.com/maps/dir/?api=1&destination=Paris&travelmode=flying',
      destination:'Paris', mode:'flying', apple:false), isNull);
    expect(checkedBrainDirections(
      Uri.https('maps.apple.com','/directions',{'destination':'Paris\u0000','mode':'walking'}).toString(),
      destination:'Paris\u0000', mode:'walking', apple:true), isNull);
  });

  Future<BrainApi> fixtureApi() async {
    final auth = BrainAuthController(
      client: MockClient((_) async => http.Response(jsonEncode({'session': {
        'access_token': fixtureToken(), 'refresh_token':'fixture-refresh',
      }}),200)),
      tokenStore: KorlixTokenStore(useSecureStorage:false, namespace:'directions_fixture'),
    );
    addTearDown(auth.dispose);
    await auth.authenticate(email:'fixture@example.test',password:'fixture');
    final api = BrainApi(auth,client:MockClient((request) async {
      if(request.method=='GET') return http.Response(jsonEncode({'directionsAvailable':true}),200);
      final body = jsonDecode(request.body) as Map;
      final destination = body['destination'] as String, mode = body['mode'] as String;
      return http.Response(jsonEncode({
        'destination':destination, 'mode':mode, 'requiresConfirmation':true,
        'googleMapsUrl':Uri.https('www.google.com','/maps/dir/',{'api':'1','destination':destination,'travelmode':mode}).toString(),
        'appleMapsUrl':Uri.https('maps.apple.com','/directions',{'destination':destination,'mode':mode}).toString(),
      }),200);
    }));
    addTearDown(api.dispose);
    return api;
  }

  testWidgets('directions pause before launching and require the explicit confirmation', (tester) async {
    final api = await fixtureApi();
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(home:BrainDirectionsScreen(
      api:api, initialDestination:'1000 Fifth Avenue, New York, NY 10028',
      beforeOpen:() async { events.add('pause'); },
      launcher:(uri) async { events.add('launch:${uri.host}'); return true; },
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Google Maps directions'));
    await tester.tap(find.text('Google Maps directions'));
    await tester.pumpAndSettle();
    expect(events,isEmpty);
    expect(find.text('Open Google Maps?'),findsOneWidget);
    await tester.tap(find.text('Open directions'));
    await tester.pumpAndSettle();
    expect(events,['pause','launch:www.google.com']);
    await api.auth.signOut();
    await tester.pumpAndSettle();
  });

  testWidgets('account change removes only the owned confirmation and never opens Maps', (tester) async {
    final api = await fixtureApi();
    final navigator = GlobalKey<NavigatorState>();
    var launches=0, pauses=0;
    await tester.pumpWidget(MaterialApp(navigatorKey:navigator,home:BrainDirectionsScreen(
      api:api,initialDestination:'1000 Fifth Avenue, New York, NY 10028',
      beforeOpen:() async { pauses++; },
      launcher:(_) async { launches++; return true; },
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Google Maps directions'));
    await tester.tap(find.text('Google Maps directions'));
    await tester.pumpAndSettle();
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder:(_) => const Scaffold(body:Center(child:Text('Unrelated page'))),
    ));
    await tester.pumpAndSettle();
    await api.auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Unrelated page'),findsOneWidget);
    expect(launches,0);
    expect(pauses,0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Open Google Maps?'),findsNothing);
    expect(find.text('Your account changed. Close this screen and open directions again.'),findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,isEmpty);
  });
}
