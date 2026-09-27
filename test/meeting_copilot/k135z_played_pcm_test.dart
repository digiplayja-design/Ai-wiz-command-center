import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_played_pcm.dart';

class Sink implements K135zPcmSink {
  bool active = true;
  final packets = <Uint8List>[];
  void write(Uint8List pcm) => packets.add(pcm);
  void close() { active = false; }
  int get bytes => packets.fold(0, (n, p) => n + p.length);
}

void main() {
  test('only played samples are sent; Silence excludes the unheard tail', () {
    var seconds = 0.0;
    final sink = Sink();
    final p = K135zPlayedPcm(channels: [Float32List.fromList(List.filled(48000, .5))],
      sampleRate: 24000, playedSeconds: () => seconds, sinkFactory: (_) => sink);
    expect(sink.bytes, 0);
    seconds = .5;p.flush();expect(sink.bytes, 16000);
    seconds = .75;p.finish();expect(sink.bytes, 24000);
    seconds = 2;p.flush();expect(sink.bytes, 24000);
    expect(ByteData.sublistView(sink.packets.first).getInt16(0, Endian.little), 16384);
  });
  test('suspended audio clocks do not record unplayed generated speech', () {
    var seconds = 0.0;
    final sink = Sink();
    final p = K135zPlayedPcm(channels: [Float32List(32000)], sampleRate: 16000,
      playedSeconds: () => seconds, sinkFactory: (_) => sink);
    p.flush();p.flush();expect(sink.bytes, 0);
    seconds = .1;p.flush();p.flush();expect(sink.bytes, 3200);
    p.finish();expect(sink.bytes, 3200);
  });
  test('a recording begun during a reply excludes earlier playback', () {
    var seconds = 0.0, armed = false;
    final sink = Sink();
    final p = K135zPlayedPcm(channels: [Float32List(48000)], sampleRate: 16000,
      playedSeconds: () => seconds, sinkFactory: (_) => armed ? sink : null);
    seconds = 1;p.flush();armed = true;seconds = 1.5;p.flush();
    expect(sink.bytes, 0);
    seconds = 2;p.finish();expect(sink.bytes, 16000);
  });
  test('stereo mixes to mono, clips safely, and emits bounded packets', () {
    var seconds = 0.0;
    final sink = Sink();
    final p = K135zPlayedPcm(channels: [Float32List.fromList(List.filled(48000, 1.5)),
      Float32List.fromList(List.filled(48000, 1.5))], sampleRate: 48000,
      playedSeconds: () => seconds, sinkFactory: (_) => sink);
    seconds = 2;p.finish();
    expect(sink.bytes, 32000);expect(sink.packets.every((b) => b.length <= 16000), true);
    expect(ByteData.sublistView(sink.packets.first).getInt16(0, Endian.little), 32767);
  });
  test('a disabled sink cannot receive later audio', () {
    var seconds = 0.0;
    final sink = Sink();
    final p = K135zPlayedPcm(channels: [Float32List(32000)], sampleRate: 16000,
      playedSeconds: () => seconds, sinkFactory: (_) => sink.active ? sink : null);
    seconds = .5;p.flush();sink.close();seconds = 1;p.finish();
    expect(sink.bytes, 16000);
  });
}
