import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../core/app_translations.dart';
import '../../data/database/db_library.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/library_entity.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper_opener.dart';
import '../../utils/helper_toast.dart';
import '../player/player_multi_view.dart';
import 'home_controller.dart';
import 'home_panel/home_panel_playlist.dart';

mixin LocalVideoSelection {
  final selectedVideos = <Videos>{}.obs;
  bool get isClosed;
  int get selectionRevision;
  Iterable<Videos> get selectionSource;
  Future<void> refreshSelectionFiles();

  bool sameVideo(Videos a, Videos b) => a == b || a.id != null && a.id!.isNotEmpty && a.id == b.id;
  bool isSelected(Videos video) => selectedVideos.any((item) => sameVideo(item, video));
  List<Videos> get selectedInOrder {
    final result = <Videos>[];
    final seen = <Object>{};
    for (final video in selectionSource) {
      if (isSelected(video) && seen.add((video.id ?? '').isEmpty ? video : video.id!)) result.add(video);
    }
    return result;
  }

  void toggleSelection(Videos video) {
    if (isClosed || !selectionSource.any((item) => sameVideo(item, video))) return;
    if (isSelected(video)) { selectedVideos.removeWhere((item) => sameVideo(item, video)); } else { selectedVideos.add(video); }
  }

  Future<void> performSelectionAction(String action, List<Videos> selected) async {
    if (isClosed || selected.isEmpty) return;
    switch (action) {
      case 'play':
        await HelperOpener.openVideoPlaylist(selected);
        break;
      case 'playMulti':
        await Get.to(() => const PlayerMultiView(), arguments: selected);
        break;
      case 'cart':
        final home = Get.find<HomeController>();
        for (final video in selected) { home.addToCart(video); }
        await HelperToast.success('Selected videos are in cart'.tr);
        break;
      case 'playlist':
        await HomePanelPlaylist.showDialogAddToPlaylistItem(selected);
        break;
      case 'favorite':
        for (final video in selected) { await DBVideos.addToFavorite(video); }
        await HelperToast.success('Added @{length} video(s) to favorite'.trNamed({'length': '${selected.length}'}));
        break;
    }
  }

  Future<void> applyFileMoves(Map<String, Videos> files, Map<String, String> paths, List<String> missing) async {
    if (paths.isEmpty && missing.isEmpty) return;
    final libraries = await DBLibrary.getAll();
    final roots = libraries.map((library) => library.rootFolder ?? '').where((root) => root.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final moves = <Map<String, String>>[];
    for (final entry in paths.entries) {
      final existing = await DBVideos.getByVideoPath(entry.value);
      if (existing != null && existing.id != files[entry.key]?.id) {
        throw StateError('The destination is already in the library: @{value}'.trNamed({'value': '${entry.value}'}));
      }
      moves.add({
        'oldPath': entry.key,
        'newPath': entry.value,
        'newRoot': roots.firstWhere((root) => p.isWithin(root, entry.value), orElse: () => p.dirname(entry.value)),
      });
    }
    final snapshots = <Library>[];
    for (final library in libraries) {
      final previous = library.videos ?? <String>[];
      final next = previous.where((path) => !paths.containsKey(path) && !missing.contains(path)).toSet();
      next.addAll(moves.where((move) => move['newRoot'] == library.rootFolder).map((move) => move['newPath']!));
      if (next.length == previous.length && next.containsAll(previous)) continue;
      library.videos = next.toList();
      library.totalVideo = next.length;
      snapshots.add(library);
    }
    await DBLibrary.commitScan(snapshots, moves: moves);
    for (final move in moves) {
      final video = files[move['oldPath']]!;
      video.videoPath = move['newPath'];
      video.rootPath = move['newRoot'];
    }
    if (!isClosed) await refreshSelectionFiles();
  }

}
