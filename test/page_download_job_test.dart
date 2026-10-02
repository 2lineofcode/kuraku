import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/modules/home/page_download/page_download_job.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late HttpServer server;
  late String url;
  var segment = <int>[];
  final binary = p.absolute('assets/javit_dl');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('javit download test ');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/video';
    server.listen((request) async {
      if (request.uri.path == '/hls') {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n');
      } else if (request.uri.path == '/segment.ts') {
        request.response.add(segment);
      } else if (request.uri.path == '/error') {
        request.response.statusCode = 403;
      } else if (request.uri.path == '/html') {
        request.response.write('<!DOCTYPE html><html>player</html>');
      } else {
        request.response.add(List.generate(2048, (i) => i % 256));
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<String> script(String body) async {
    final file = File(p.join(directory.path, 'downloader'));
    await file.writeAsString('#!/bin/sh\n$body');
    await Process.run('/bin/chmod', ['+x', file.path]);
    return file.path;
  }

  test('arguments match each command, preserve URL and paths without shell quoting', () {
    for (final mode in ['auto', 'extract', 'hls', 'file', 'youtube']) {
      final request = DownloadRequest(url: '$url?token=a&b=\$(touch nope)', directory: directory.path, filename: 'a b.mp4', mode: mode);
      request.validate();
      final args = request.arguments(p.join(directory.path, 'cache'));
      expect(args.first, mode == 'auto' ? request.url : mode);
      expect(args, contains(request.url));
      expect(args, contains(p.join(directory.path, 'a b.mp4')));
      expect(args.contains('--auto'), ['auto', 'extract', 'hls'].contains(mode));
      expect(args, isNot(contains('-u')));
      expect(args, isNot(contains('-rawurl')));
    }
    expect(() => DownloadRequest(url: url, directory: directory.path, filename: '../outside.mp4').validate(), throwsFormatException);
    expect(() => DownloadRequest(url: url, directory: directory.path, concurrency: 65).validate(), throwsFormatException);
    expect(() => DownloadRequest(url: 'file:///tmp/video', directory: directory.path).validate(), throwsFormatException);
    expect(() => DownloadRequest(url: url, directory: directory.path, mode: 'auto').validate(), throwsFormatException);
  });

  test('real binary downloads a direct file and refuses replacement', () async {
    final request = DownloadRequest(url: url, directory: directory.path, filename: 'movie file.bin', mode: 'file');
    final job = PageDownloadJob();
    await job.start(request, binary: binary, cache: p.join(directory.path, 'cache'));
    expect(job.status, 'Completed', reason: job.logs.join('\n'));
    expect(job.exitCode, 0);
    expect(await File(job.outputPath).readAsBytes(), List.generate(2048, (i) => i % 256));
    await job.start(request, binary: binary, cache: p.join(directory.path, 'cache'));
    expect(job.status, 'Failed');
    expect(job.error, contains('existing file'));
    expect(await File(p.join(directory.path, request.filename)).length(), 2048);
  });

  test('real binary auto rejects HTML and records nonzero HTTP failure', () async {
    final job = PageDownloadJob();
    await job.start(DownloadRequest(url: url.replaceFirst('/video', '/html'), directory: directory.path, filename: 'page.mp4', mode: 'auto'), binary: binary, cache: p.join(directory.path, 'cache'));
    expect(job.status, 'Failed');
    expect(job.error, contains('HTML'));
    await job.start(DownloadRequest(url: url.replaceFirst('/video', '/error'), directory: directory.path, filename: 'error.bin', mode: 'file', retries: 0), binary: binary, cache: p.join(directory.path, 'cache'));
    expect(job.status, 'Failed');
    expect(job.exitCode, isNot(0));
    expect(await File(p.join(directory.path, 'error.bin')).exists(), isFalse);
  });

  test('real binary detects HLS and remuxes a playable MP4', () async {
    final source = p.join(directory.path, 'source.ts');
    final generated = await Process.run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=black:s=64x64:r=10', '-t', '1', '-c:v', 'libx264', '-f', 'mpegts', source]);
    expect(generated.exitCode, 0, reason: '${generated.stderr}');
    segment = await File(source).readAsBytes();
    final job = PageDownloadJob();
    await job.start(DownloadRequest(url: url.replaceFirst('/video', '/hls'), directory: directory.path, filename: 'hls result.any', mode: 'auto'), binary: binary, cache: p.join(directory.path, 'cache'));
    expect(job.status, 'Completed', reason: job.logs.join('\n'));
    expect(job.outputPath, endsWith('.mp4'));
    expect(job.logs.any((line) => line.contains('Remuxing to MP4')), isTrue);
    final probe = await Process.run('ffprobe', ['-v', 'error', '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', job.outputPath]);
    expect(probe.exitCode, 0);
    expect(probe.stdout.toString(), contains('h264'));
  });

  test('chunked extraction waits for user selection and background capture; DASH is disabled', () async {
    final executable = await script(r'''
printf '[1] [DASH (unsupported)] https://cdn.test/ad.mpd\n[2] [FILE] https://cdn.test/'
sleep 0.1
printf 'movie.mp4\nCapture complete. Enter a media number to download, list, or q to quit.\n'
read selected
[ "$selected" = 2 ] || exit 1
printf 'Downloading: 50%% (1/2)\rRemuxing to MP4...\n'
printf 'video data' > "$4"
printf 'Downloaded %s (1s)\n' "$4"
''');
    final ready = Completer<void>();
    late PageDownloadJob job;
    job = PageDownloadJob(onChanged: () {
      if (job.canSelect && !ready.isCompleted) ready.complete();
    });
    final download = job.start(DownloadRequest(url: url, directory: directory.path, filename: 'selected.mp4', headless: true), binary: executable, cache: p.join(directory.path, 'cache'));
    await ready.future.timeout(const Duration(seconds: 5));
    expect(job.candidates.length, 2);
    expect(job.candidates.first.supported, isFalse);
    expect(await File(p.join(directory.path, 'selected.mp4')).exists(), isFalse);
    await job.select(job.candidates.last);
    await download;
    expect(job.status, 'Completed', reason: job.logs.join('\n'));
    expect(job.logs, contains('Downloading: 50% (1/2)'));
    expect(job.logs, contains('Remuxing to MP4...'));
  });

  test('automatic extraction naming resolves relative paths inside the output folder', () async {
    final executable = await script(r'''
printf '[1] [FILE] https://cdn.test/video.mp4\n'
read selected
printf 'Save to: Movie title (2).mp4\n'
printf 'video data' > 'Movie title (2).mp4'
printf 'Downloaded Movie title (2).mp4 (1s)\n'
''');
    final ready = Completer<void>();
    late PageDownloadJob job;
    job = PageDownloadJob(onChanged: () {
      if (job.canSelect && !ready.isCompleted) ready.complete();
    });
    final download = job.start(DownloadRequest(url: url, directory: directory.path), binary: executable, cache: p.join(directory.path, 'cache'));
    await ready.future.timeout(const Duration(seconds: 5));
    await job.select(job.candidates.first);
    await download;
    expect(job.status, 'Completed', reason: job.logs.join('\n'));
    expect(job.outputPath, p.join(directory.path, 'Movie title (2).mp4'));
    expect(await File(job.outputPath).readAsString(), 'video data');
  });

  test('extraction refuses a split overwrite prompt without a newline', () async {
    final executable = await script(r'''
 printf 'Output already exists: %s. Over' "$4"
 sleep 0.1
 printf 'write? [y/N]: '
 read answer
 [ "$answer" = n ] || exit 2
 printf '\nError: overwrite declined; existing file kept\n' >&2
 exit 1
''');
    final output = File(p.join(directory.path, 'existing.mp4'));
    await output.writeAsString('original');
    final job = PageDownloadJob();
    await job.start(DownloadRequest(url: url, directory: directory.path, filename: 'existing.mp4'), binary: executable, cache: p.join(directory.path, 'cache'), deadline: const Duration(seconds: 5));
    expect(job.status, 'Failed');
    expect(job.exitCode, 1);
    expect(await output.readAsString(), 'original');
  });

  test('exit zero without completion or with a symlink never succeeds', () async {
    final job = PageDownloadJob();
    var executable = await script('exit 0\n');
    final request = DownloadRequest(url: url, directory: directory.path, filename: 'missing.mp4');
    await job.start(request, binary: executable, cache: p.join(directory.path, 'cache'));
    expect(job.status, 'Failed');
    executable = await script(r'''
printf data > "$4.real"
ln -s "$4.real" "$4"
printf 'Downloaded %s (1s)\n' "$4"
''');
    await job.start(request, binary: executable, cache: p.join(directory.path, 'cache'));
    expect(job.status, 'Failed');
  });

  test('cancellation uses SIGTERM and remains cancelled even when process exits zero', () async {
    final executable = await script(r'''
trap 'exit 0' TERM
printf 'Ready for cancellation\n'
while :; do sleep 0.1; done
''');
    final ready = Completer<void>();
    late PageDownloadJob job;
    job = PageDownloadJob(onChanged: () {
      if (job.logs.contains('Ready for cancellation') && !ready.isCompleted) ready.complete();
    });
    final download = job.start(DownloadRequest(url: url, directory: directory.path), binary: executable, cache: p.join(directory.path, 'cache'));
    await ready.future.timeout(const Duration(seconds: 5));
    expect(() => job.start(DownloadRequest(url: url, directory: directory.path), binary: executable, cache: p.join(directory.path, 'cache')), throwsStateError);
    job.cancel();
    await download;
    expect(job.status, 'Cancelled');
    expect(job.exitCode, 0);
    expect(job.process, isNull);
    await job.start(DownloadRequest(url: url, directory: directory.path), binary: executable, cache: p.join(directory.path, 'cache'), deadline: const Duration(milliseconds: 100));
    expect(job.status, 'Failed');
    expect(job.error, contains('deadline'));
  });
}
