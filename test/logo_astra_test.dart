import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/imagine_studio/imagine_client.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_catalog.dart';
import 'imagine_studio_test.dart' as imagine;
import 'logo_studio_test.dart' as logo;

const direction = {
  'conceptName': 'Shared Stem',
  'summary': 'A botanical silhouette with warm, readable lettering.',
  'planningModel': 'gpt-6-astra',
  'reasoningEffort': 'max',
};

Future<void> replyWithDirection(imagine.Studio s, dynamic value) async {
  s.invalidBody = jsonEncode({
    ...jsonDecode((await s.response()).body) as Map<String, dynamic>,
    'logoDirection': value,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'logo requests carry the complete selected brief and retain Astra metadata',
    () async {
      final s = imagine.Studio();
      await replyWithDirection(s, direction);
      final result = await s.client.create(
        logo.sample.aiBrief,
        logoBrief: logo.sample.json,
        language: 'fr',
      );
      expect(s.requests.single['logoBrief'], logo.sample.json);
      expect(s.requests.single['language'], 'fr');
      expect(s.requests.single.containsKey('model'), false);
      expect(result!.logoDirection!.planningModel, 'gpt-6-astra');
      expect(result.logoDirection!.reasoningEffort, 'max');
      expect(result.logoDirection!.summary, direction['summary']);
      expect(s.client.results.single.logoDirection, result.logoDirection);
      s.client.dispose();
    },
  );

  test('ordinary Imagine requests omit logo planning data', () async {
    final s = imagine.Studio();
    final result = await s.client.create(
      const ImagineBrief(prompt: 'A garden'),
    );
    expect(s.requests.single.containsKey('logoBrief'), false);
    expect(result!.logoDirection, isNull);
    s.client.dispose();
  });

  test(
    'a pending logo cannot be submitted twice and planning failures are not retried',
    () async {
      final s = imagine.Studio()..pending = Completer<http.Response>();
      final pending = s.client.create(
        logo.sample.aiBrief,
        logoBrief: logo.sample.json,
      );
      final rejected = expectLater(pending, throwsA(isA<ImagineException>()));
      expect(
        await s.client.create(logo.sample.aiBrief, logoBrief: logo.sample.json),
        isNull,
      );
      await Future<void>.delayed(Duration.zero);
      s.pending!.complete(
        http.Response(
          jsonEncode({
            'details':
                'Astra could not complete the logo design plan. No generation credit was used.',
          }),
          503,
        ),
      );
      await rejected;
      expect(s.requests.length, 1);
      expect(s.client.results, isEmpty);
      expect(s.client.error, contains('No generation credit was used'));
      expect(s.client.busy, false);
      expect(s.client.draft.lettering, contains(logo.sample.name));
      s.client.dispose();
    },
  );

  test(
    'late creative direction and artwork cannot cross an account change',
    () async {
      final s = imagine.Studio()..pending = Completer<http.Response>();
      await replyWithDirection(s, direction);
      final pending = s.client.create(
        logo.sample.aiBrief,
        logoBrief: logo.sample.json,
      );
      final rejected = expectLater(pending, throwsA(isA<ImagineException>()));
      await Future<void>.delayed(Duration.zero);
      s.change();
      s.pending!.complete(await s.response());
      await rejected;
      expect(s.client.results, isEmpty);
      expect(s.client.available, false);
      s.client.dispose();
    },
  );

  test(
    'malformed optional summaries are ignored without losing a usable PNG',
    () async {
      for (final value in [
        null,
        [],
        {...direction, 'summary': 42},
        {...direction, 'summary': 'x' * 801},
      ]) {
        final s = imagine.Studio();
        await replyWithDirection(s, value);
        final result = await s.client.create(
          logo.sample.aiBrief,
          logoBrief: logo.sample.json,
        );
        expect(result!.logoDirection, isNull);
        expect(result.width, 8);
        expect(s.client.results.length, 1);
        s.client.dispose();
      }
    },
  );
}
