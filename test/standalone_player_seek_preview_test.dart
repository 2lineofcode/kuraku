import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/modules/standalone_player/standalone_player_seek_preview.dart';

void main() {
  testWidgets('debounces movement and keeps only the latest pending frame', (tester) async {
    final jobs = <StandaloneSeekPreviewJob>[];
    final results = <Completer<Uint8List?>>[];
    final preview = StandalonePlayerSeekPreview(extract: (job) {
      jobs.add(job);
      final result = Completer<Uint8List?>();
      results.add(result);
      return result.future;
    });
    addTearDown(preview.dispose);

    preview.request('video.mp4', 12);
    expect(preview.isLoading, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    preview.request('video.mp4', 26);
    await tester.pump(const Duration(milliseconds: 179));
    expect(jobs, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(jobs.single.second, 20);

    preview.request('video.mp4', 31);
    preview.request('video.mp4', 47);
    await tester.pump(const Duration(milliseconds: 180));
    expect(jobs, hasLength(1));
    expect(jobs.first.cancelled, isTrue);
    results.first.complete(Uint8List.fromList([1]));
    await tester.pump();
    expect(preview.bytes, isNull);
    expect(jobs, hasLength(2));
    expect(preview.isLoading, isTrue);
    expect(jobs.last.second, 40);
    results.last.complete(Uint8List.fromList([2]));
    await tester.pump();
    expect(preview.bytes, [2]);
    expect(preview.isLoading, isFalse);

    preview.request('video.mp4', 49);
    await tester.pump(const Duration(milliseconds: 200));
    expect(jobs, hasLength(2));
  });

  testWidgets('leaving and changing videos discard in-flight results, including second 90', (tester) async {
    final jobs = <StandaloneSeekPreviewJob>[];
    final results = <Completer<Uint8List?>>[];
    final preview = StandalonePlayerSeekPreview(extract: (job) {
      jobs.add(job);
      final result = Completer<Uint8List?>();
      results.add(result);
      return result.future;
    });
    addTearDown(preview.dispose);
    preview.request('first.mp4', 90);
    await tester.pump(const Duration(milliseconds: 180));
    expect(jobs.single.second, 90);
    preview.request('second.mp4', 90);
    results.first.complete(Uint8List.fromList([1]));
    await tester.pump();
    expect(preview.bytes, isNull);
    await tester.pump(const Duration(milliseconds: 180));
    expect(jobs.last.path, 'second.mp4');
    preview.clear();
    expect(jobs.last.cancelled, isTrue);
    expect(preview.isLoading, isFalse);
    results.last.complete(Uint8List.fromList([2]));
    await tester.pump();
    expect(preview.bytes, isNull);

    preview.request('third.mp4', 10);
    preview.clear();
    await tester.pump(const Duration(seconds: 1));
    expect(jobs, hasLength(2));
  });

  testWidgets('failure does not loop and a later request recovers', (tester) async {
    var calls = 0;
    final preview = StandalonePlayerSeekPreview(extract: (job) async {
      calls++;
      if (calls == 1) throw StateError('Unsupported video');
      return Uint8List.fromList([job.second]);
    });
    addTearDown(preview.dispose);
    preview.request('video.mp4', -1);
    await tester.pump(const Duration(milliseconds: 180));
    expect(calls, 1);
    expect(preview.bytes, isNull);
    expect(preview.isLoading, isFalse);
    preview.request('video.mp4', 20);
    await tester.pump(const Duration(milliseconds: 180));
    expect(preview.bytes, [20]);
    preview.request('', 0);
    expect(preview.bytes, isNull);
  });

  testWidgets('dispose cancels work without notifying or starting pending work', (tester) async {
    final result = Completer<Uint8List?>();
    late StandaloneSeekPreviewJob active;
    var calls = 0;
    var notifications = 0;
    final preview = StandalonePlayerSeekPreview(extract: (job) {
      calls++;
      active = job;
      return result.future;
    })..addListener(() => notifications++);
    preview.request('video.mp4', 0);
    await tester.pump(const Duration(milliseconds: 180));
    preview.request('video.mp4', 10);
    final beforeDispose = notifications;
    preview.dispose();
    expect(active.cancelled, isTrue);
    result.complete(Uint8List.fromList([1]));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    expect(notifications, beforeDispose);
  });
}
