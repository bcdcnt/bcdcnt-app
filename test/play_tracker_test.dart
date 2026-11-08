import 'package:flutter_test/flutter_test.dart';
import 'package:bcdcnt/services/play_tracker.dart';

void main() {
  late List<LogListenPayload> sent;
  late PlayTracker t;

  setUp(() {
    sent = [];
    t = PlayTracker((p) async => sent.add(p));
  });

  Future<void> listen(Duration d) async {
    await Future<void>.delayed(d);
    t.onTimeUpdate();
  }

  test('5 s of listening counts, as on the web', () async {
    t.startSession(songId: '1', objectType: 'song', source: 'manual');
    await listen(const Duration(milliseconds: 5200));
    t.endSession(reason: 'skip');
    expect(sent, hasLength(1));
    expect(sent.single.toVariables()['source'], 'direct');
  });

  test('under 5 s does not count', () async {
    t.startSession(songId: '2', objectType: 'song');
    await listen(const Duration(seconds: 2));
    t.endSession();
    expect(sent, isEmpty);
  });

  test('flush sends once and the session keeps going', () async {
    t.startSession(songId: '3', objectType: 'folk', source: 'auto-next');
    await listen(const Duration(milliseconds: 5200));
    t.flush();
    expect(sent, hasLength(1));
    expect(sent.single.toVariables()['source'], 'auto-next');
    await listen(const Duration(milliseconds: 300));
    t.endSession(reason: 'completed');
    expect(sent, hasLength(1));
  });

  test('flush before 5 s waits for the song to end', () async {
    t.startSession(songId: '4', objectType: 'song');
    await listen(const Duration(seconds: 1));
    t.flush();
    expect(sent, isEmpty);
    await listen(const Duration(milliseconds: 4500));
    t.endSession(reason: 'completed');
    expect(sent, hasLength(1));
  });
}
