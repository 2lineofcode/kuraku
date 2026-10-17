import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/api/api_javtrailers.dart';
import '../../data/models/videos_entity.dart';
import 'widget_controls.dart';
import 'widget_surfaces.dart';

class DesktopTrailer extends StatefulWidget {
  const DesktopTrailer({super.key, required this.video, required this.urls});
  final Videos video;
  final List<String> urls;

  @override
  State<DesktopTrailer> createState() => _DesktopTrailerState();
}

class _DesktopTrailerState extends State<DesktopTrailer> {
  late final player = Player();
  late final controller = VideoController(player);
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await player.setVolume(10);
      await player.setRate(1.1);
      for (final url in widget.urls) {
        if (!mounted) return;
        final ready = Completer<void>();
        final subscription = player.stream.width.listen((width) {
          if (width != null && width > 0 && !ready.isCompleted) ready.complete();
        });
        final errors = player.stream.error.listen((message) {
          if (!ready.isCompleted) ready.completeError(StateError(message));
        });
        try {
          await Future.wait([
            player.open(Media(url, httpHeaders: Uri.parse(url).host == 'media.javtrailers.com' ? ApiJavTrailers.headers : const {})),
            ready.future.timeout(const Duration(seconds: 20)),
          ]);
          if (mounted) setState(() => loading = false);
          return;
        } catch (e) {
          if (!mounted) return;
          if (url == widget.urls.last) rethrow;
          await player.stop();
        } finally {
          await subscription.cancel();
          await errors.cancel();
        }
      }
    } catch (e) {
      if (mounted) setState(() { loading = false; error = '$e'; });
    }
  }

  @override
  void dispose() {
    unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(child: SizedBox(
    width: 960,
    height: MediaQuery.sizeOf(context).height * .8,
    child: Column(children: [
      Row(children: [
        const SizedBox(width: 12),
        Expanded(child: Text('${widget.video.videoCode ?? ''} ${widget.video.title ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis)),
        AppIconButton(tooltip: 'Close'.tr, icon: const Icon(Icons.close), onPressed: () => Get.back()),
      ]),
      Expanded(child: error != null ? Center(child: Text(error!)) : Stack(children: [
        Video(controller: controller, controls: MaterialDesktopVideoControls),
        if (loading) const Center(child: CircularProgressIndicator()),
      ])),
    ]),
  ));
}
