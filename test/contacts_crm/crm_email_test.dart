import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_client.dart';
import 'package:ai_wiz_command_center/contacts_crm/crm_email_screen.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_style.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_screen.dart';
import 'contacts_screen_test.dart' as fixture;
void main(){
 for(final width in [390.0,1440.0]){
 testWidgets('CRM email editor saves exact changes paused at width $width',(t)async{
  t.view.physicalSize=Size(width,1000);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final requests=<Map<String,dynamic>>[];
  final client=ContactsClient(backendBaseUrl:'https://fixture.invalid',headersBuilder:()=>{},client:MockClient((q)async{if(q.method=='POST')requests.add(jsonDecode(q.body));return http.Response(jsonEncode(q.method=='GET'?{'rules':[],'jobs':[],'capabilities':{'ready':true,'reply_to':'owner@example.com'}}:{'saved':true,'enabled':false}),200);}));
  await t.pumpWidget(MaterialApp(theme:CrmStyle.theme,home:CrmEmailScreen(client:client,contact:fixture.sample)));
  await t.pumpAndSettle();expect(t.takeException(),isNull);expect(find.text('New follow-up email'),findsOneWidget);
  await t.enterText(find.byKey(const Key('crm-email-subject')),'Revised follow-up');await t.enterText(find.byKey(const Key('crm-email-body')),'Please send the updated request.');
  await t.tap(find.text('Save paused'));await t.pumpAndSettle();expect(t.takeException(),isNull);expect(requests.length,1);expect(requests.single['subject'],'Revised follow-up');expect(requests.single['body'],'Please send the updated request.');expect(requests.single['delivery_mode'],'review');expect(requests.single.containsKey('enabled'),false);await t.pumpWidget(const SizedBox());client.dispose();
 });}
 testWidgets('Enable requires recipient/message review; cancel makes no request',(t)async{
  t.view.physicalSize=const Size(1000,1200);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final requests=<Map<String,dynamic>>[],rule={'id':'r','contact_id':'c','version':3,'contact_name':'Sam','email':'sam@example.com','follow_up_on':'2026-10-08','subject':'Follow up','body':'Hello Sam','send_hour':9,'timezone':'UTC','delivery_mode':'automatic','enabled':false};
  final client=ContactsClient(backendBaseUrl:'https://fixture.invalid',headersBuilder:()=>{},client:MockClient((q)async{if(q.method=='POST')requests.add(jsonDecode(q.body));return http.Response(jsonEncode(q.method=='GET'?{'rules':[rule],'jobs':[],'capabilities':{'ready':true,'reply_to':'owner@example.com'}}:{}),200);}));
  await t.pumpWidget(MaterialApp(theme:CrmStyle.theme,home:CrmEmailScreen(client:client)));await t.pumpAndSettle();await t.ensureVisible(find.text('Enable'));await t.pumpAndSettle();await t.tap(find.text('Enable'));await t.pumpAndSettle();expect(find.textContaining('sam@example.com').last,findsOneWidget);await t.tap(find.text('Cancel'));await t.pumpAndSettle();expect(requests,isEmpty);await t.tap(find.text('Enable'));await t.pumpAndSettle();await t.tap(find.text('Confirm'));await t.pumpAndSettle();expect(requests.single,{'action':'toggle','id':'r','version':3,'enabled':true,'confirmed':true});await t.pumpWidget(const SizedBox());client.dispose();
 });
 testWidgets('CRM workspace buttons fit desktop and open email',(t)async{
  t.view.physicalSize=const Size(1440,1000);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final original=FlutterError.onError;FlutterError.onError=(d){debugPrint(d.toString());original?.call(d);};addTearDown(()=>FlutterError.onError=original);
  await t.pumpWidget(MaterialApp(home:ContactsScreen(client:fixture.api((q)=>q.url.path.endsWith('/email')?fixture.result({'rules':[],'jobs':[],'capabilities':{'ready':true}}):fixture.normal(q)))));await t.pumpAndSettle();expect(t.takeException(),isNull);expect(find.byKey(const Key('crm-k-nova')),findsOneWidget);await t.tap(find.byKey(const Key('crm-autonomous-email')));await t.pumpAndSettle();expect(find.text('CRM · Autonomous email'),findsOneWidget);
 });
}
