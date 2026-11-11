import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:korlix_brain/voice_usage_guard.dart';

http.Response session() => http.Response('v=', 200, headers: {
  'x-korlix-live-convo-session-id':'session-one',
  'x-korlix-live-convo-max-seconds':'3600',
  'x-korlix-live-convo-max-responses':'10000',
}, request:http.Request('POST',Uri.parse('https://example.test/api/live-convo/session')));

http.Response okay() => http.Response('{"ok":true,"allowed":true}',200);
Map<String,dynamic> response(String id) => {
  'type':'response.done',
  'response': {'id':id,'usage':{'total_tokens':20,'input_tokens':10,'output_tokens':10}},
};

void main() {
  test('a delayed heartbeat is sent immediately without requiring an exact 15-second tick', () async {
    var now=DateTime(2026);
    var reports=0;
    final guard=KorlixLiveConvoUsageGuard(now:()=>now,scheduleHeartbeat:false,
      reportUsage:(body)async{reports++;return okay();});
    await guard.beginFromSessionResponse(session(),onLimitReached:(_)async{});
    expect(reports,1);
    now=now.add(const Duration(seconds:16));await guard.heartbeat();expect(reports,2);
    now=now.add(const Duration(seconds:29));await guard.heartbeat();expect(reports,3);
    await guard.end();now=now.add(const Duration(minutes:5));await guard.heartbeat();
    expect(reports,4);expect(guard.endConfirmed,isTrue);expect(guard.elapsedSeconds,45);
  });

  test('concurrent event reports coalesce; final report waits and includes every cumulative token', () async {
    final bodies=<Map<String,dynamic>>[];
    Completer<http.Response>? blocked;
    var inFlight=0,maximum=0;
    final guard=KorlixLiveConvoUsageGuard(scheduleHeartbeat:false,reportUsage:(body)async{
      bodies.add(Map.from(body));inFlight++;if(inFlight>maximum)maximum=inFlight;
      final result=blocked==null?okay():await blocked!.future;
      inFlight--;return result;
    });
    await guard.beginFromSessionResponse(session(),onLimitReached:(_)async{});
    blocked=Completer<http.Response>();
    final one=guard.observeServerEvent(response('one'));
    final two=guard.observeServerEvent(response('two'));
    final end=guard.end(reason:'user_paused');
    expect(bodies.length,2);expect(bodies.last['ended'],false);
    final completion=blocked;blocked=null;completion!.complete(okay());
    await Future.wait([one,two,end]);
    expect(maximum,1);expect(bodies.length,3);
    expect(bodies.last['responseCount'],2);expect(bodies.last['totalTokens'],40);
    expect(bodies.last['ended'],true);expect(bodies.last['endReason'],'user_paused');
  });

  test('usage failure closes local audio before waiting for final metering', () async {
    var now=DateTime(2026);
    var calls=0;
    var localClosed=false;
    final guard=KorlixLiveConvoUsageGuard(now:()=>now,scheduleHeartbeat:false,reportUsage:(body)async{
      calls++;
      if(body['ended']==true){expect(localClosed,isTrue);return okay();}
      return http.Response('unavailable',503);
    });
    await guard.beginFromSessionResponse(session(),onLimitReached:(_)async{localClosed=true;});
    now=now.add(const Duration(seconds:16));await guard.heartbeat();
    now=now.add(const Duration(seconds:16));await guard.heartbeat();
    expect(localClosed,isTrue);expect(calls,4);expect(guard.endConfirmed,isTrue);
  });

  test('server acknowledgment of an ended Brain session can be a metered 429', () async {
    final guard=KorlixLiveConvoUsageGuard(scheduleHeartbeat:false,reportUsage:(body)async=>
      body['ended']==true ? http.Response(jsonEncode({'allowed':false,'usage':{
        'sessionId':'session-one','allowed':false,'limitReached':true,
      }}),429) : okay());
    await guard.beginFromSessionResponse(session(),onLimitReached:(_)async{});
    await guard.end(reason:'user_paused');expect(guard.endConfirmed,isTrue);
  });

  test('an unconfirmed final report is retryable and never falsely acknowledges Pause', () async {
    var available=false,finalReports=0;
    final guard=KorlixLiveConvoUsageGuard(scheduleHeartbeat:false,reportUsage:(body)async{
      if(body['ended']==true){finalReports++;return available?okay():http.Response('',503);}
      return okay();
    });
    await guard.beginFromSessionResponse(session(),onLimitReached:(_)async{});
    await guard.end();expect(guard.endConfirmed,isFalse);expect(finalReports,2);
    available=true;await guard.end();expect(guard.endConfirmed,isTrue);expect(finalReports,3);
    await guard.end();expect(finalReports,3);
  });
}
