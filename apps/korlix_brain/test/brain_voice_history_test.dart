import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_voice_history.dart';

void main() {
  test('Pause context preserves transcript roles without storing control events', () {
    final history = BrainVoiceHistory()..begin(1);
    history.receive({'type':'transcript','role':'you','text':'We were discussing Harbor.'});
    history.receive({'type':'transcript','role':'rici','text':'What is the next step?'});
    history.receive({'type':'voiceSaved','memory':{'content':'not a transcript'}});
    expect(history.context, [
      {'role':'user','text':'We were discussing Harbor.'},
      {'role':'assistant','text':'What is the next step?'},
    ]);
    final copied = history.context;
    copied[0]['text'] = 'changed';
    expect(history.context[0]['text'], 'We were discussing Harbor.');
    history.begin(1);
    expect(history.context.length, 2);
  });

  test('Stop, a new conversation, and an account change discard resume context', () {
    final history = BrainVoiceHistory()..begin(1);
    void add() => history.receive({'type':'transcript','role':'you','text':'Private context'});
    add();history.begin(2);
    expect(history.context, isEmpty);expect(history.belongsTo(1), isFalse);
    add();history.begin(2, fresh:true);expect(history.context, isEmpty);
    add();history.clear();expect(history.context, isEmpty);expect(history.belongsTo(2), isFalse);
  });

  test('Resume context bounds recent entries and characters and deduplicates retransmission', () {
    final history = BrainVoiceHistory()..begin(1);
    for (var i=0;i<20;i++) {
      history.receive({'type':'transcript','role':'you','text':'turn $i'});
    }
    expect(history.context.length,16);expect(history.context.first['text'],'turn 4');
    history.receive({'type':'transcript','role':'you','text':'turn 19'});
    expect(history.context.length,16);
    for (var i=0;i<4;i++) {
      history.receive({'type':'transcript','role':'rici','text':'$i${'x' * 6000}'});
    }
    expect(history.context.length,3);
    expect(history.context.fold<int>(0,(sum,e)=>sum+e['text']!.length),12000);
    expect(history.context.every((e)=>e['text']!.length<=4000),isTrue);
  });

  test('Resume unmute accepts matching GA and legacy acknowledgments, never an unrelated item', () {
    Map<String,dynamic> event(String type) => {
      'type':type,
      'item':{'id':'resume_one','type':'message','role':'user',
        'content':[{'type':'input_text','text':'Bounded context'}]},
    };
    for (final type in ['conversation.item.added','conversation.item.done','conversation.item.created']) {
      expect(brainResumeAcknowledged(event(type),id:'resume_one',text:'Bounded context'),isTrue);
      expect(brainResumeAcknowledged(event(type),id:'another',text:'Bounded context'),isFalse);
      expect(brainResumeAcknowledged(event(type),id:'resume_one',text:'Different context'),isFalse);
    }
    final assistant=event('conversation.item.added');
    (assistant['item'] as Map)['role']='assistant';
    expect(brainResumeAcknowledged(assistant,id:'resume_one',text:'Bounded context'),isFalse);
    final incomplete=event('conversation.item.done');
    (incomplete['item'] as Map)['status']='incomplete';
    expect(brainResumeAcknowledged(incomplete,id:'resume_one',text:'Bounded context'),isFalse);
    expect(brainResumeAcknowledged(event('response.done'),id:'resume_one',text:'Bounded context'),isFalse);
  });
}
