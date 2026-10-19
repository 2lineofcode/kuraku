import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class StandaloneSeekPreviewJob {
  final String path;
  final int second;
  bool cancelled = false;
  int? _sessionId;
  bool _cancelSent = false;

  StandaloneSeekPreviewJob(this.path, this.second);

  Future<void> cancel() async {
    cancelled = true;
    final id = _sessionId;
    if (id == null || _cancelSent) return;
    _cancelSent = true;
    try {
      await FFmpegKit.cancel(id);
    } catch (e) {
      debugPrint('[seek-preview] cancel failed: $e');
    }
  }
}

class StandalonePlayerSeekPreview extends ChangeNotifier {
  final Future<Uint8List?> Function(StandaloneSeekPreviewJob) _extract;
  Timer? _debounce;
  StandaloneSeekPreviewJob? _target;
  StandaloneSeekPreviewJob? _active;
  bool _ready = false;
  bool _disposed = false;
  Uint8List? bytes;
  bool isLoading = false;

  StandalonePlayerSeekPreview({Future<Uint8List?> Function(StandaloneSeekPreviewJob)? extract})
      : _extract = extract ?? _extractFrame;

  void request(String path, int second) {
    if (_disposed) return;
    if (path.isEmpty) {
      clear();
      return;
    }
    second = second < 0 ? 0 : (second ~/ 10) * 10;
    if (_target?.path == path && _target?.second == second) return;
    clear();
    _target = StandaloneSeekPreviewJob(path, second);
    isLoading = true;
    notifyListeners();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      _ready = true;
      unawaited(_run());
    });
  }

  void clear() {
    _debounce?.cancel();
    _ready = false;
    _target = null;
    _active?.cancel();
    if (bytes != null || isLoading) {
      bytes = null;
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _run() async {
    if (_disposed || !_ready || _active != null || _target == null) return;
    final job = _target!;
    _active = job;
    _ready = false;
    try {
      final result = await _extract(job);
      if (!_disposed && !job.cancelled && identical(job, _target)) {
        bytes = result;
      }
    } catch (e) {
      debugPrint('[seek-preview] extraction failed: $e');
    } finally {
      if (!_disposed && identical(job, _target)) {
        isLoading = false;
        notifyListeners();
      }
      _active = null;
      // Wait for native completion before starting the latest pending request.
      unawaited(_run());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }

  static Future<Uint8List?> _extractFrame(StandaloneSeekPreviewJob job) async {
    final stat = await File(job.path).stat();
    if (job.cancelled || stat.type != FileSystemEntityType.file) return null;
    final temp = await Directory.systemTemp.createTemp('kuraku_seek_');
    Timer? timeout;
    try {
      if (job.cancelled) return null;
      final output = File(p.join(temp.path, 'frame.jpg'));
      final completed = Completer<bool>();
      final session = await FFmpegKit.executeWithArgumentsAsync([
        '-hide_banner', '-nostdin', '-loglevel', 'error', '-y',
        '-ss', '${job.second}', '-noaccurate_seek', '-skip_frame', 'nokey', '-threads', '1',
        '-i', job.path, '-map', '0:v:0', '-an', '-sn', '-dn',
        '-frames:v', '1', '-vf', 'scale=256:144:force_original_aspect_ratio=decrease:force_divisible_by=2',
        '-fps_mode', 'passthrough', '-pix_fmt', 'yuvj420p',
        '-threads', '1', '-filter_threads', '1', '-q:v', '5', '-update', '1', output.path,
      ], (session) async {
        try {
          final code = await session.getReturnCode();
          if (!completed.isCompleted) completed.complete(ReturnCode.isSuccess(code));
        } catch (e) {
          if (!completed.isCompleted) completed.complete(false);
        }
      });
      job._sessionId = session.getSessionId();
      if (job.cancelled) await job.cancel();
      timeout = Timer(const Duration(seconds: 8), job.cancel);
      final success = await completed.future;
      timeout.cancel();
      if (!success || job.cancelled || !await output.exists()) return null;
      final result = await output.readAsBytes();
      if (job.cancelled || result.isEmpty) return null;
      return result;
    } finally {
      timeout?.cancel();
      job._sessionId = null;
      await temp.delete(recursive: true);
    }
  }
}
