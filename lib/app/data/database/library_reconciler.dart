import 'dart:io';

import 'package:get/get.dart';

import '../../utils/video_file_identity.dart';
import '../models/library_entity.dart';
import '../models/videos_entity.dart';
import '_init_db.dart';
import 'db_library.dart';
import 'db_videos.dart';

typedef LibraryScanResult = ({int added, int moved, int missing, bool changed, bool retry});

mixin LibraryReconciler {
  static Future<LibraryScanResult> reconcile(List<Library> snapshots, {
    required Future<List<Videos>> Function(Library) prepareVideos,
  }) async {
    final db = Get.find<DBService>().dbMain;
    final stored = await DBVideos.getAll(includeDeleted: true);
    final previousLibraries = {for (final library in await DBLibrary.getAll()) library.id: library};
    final byPath = {for (final video in stored) video.videoPath!: video};
    final cached = <String, FileIdentity>{};
    for (final row in await db.query('video_file_identity')) {
      cached[row['video_id'] as String] = (size: row['filesize'] as int,
        modifiedAt: row['modified_at'] as int, fingerprint: row['fingerprint'] as String);
    }
    final roots = snapshots.map((library) => library.rootFolder!).toSet();
    final paths = <String, String>{};
    final sorted = List<Library>.from(snapshots)
      ..sort((a, b) => a.rootFolder!.length.compareTo(b.rootFolder!.length));
    for (final library in sorted) {
      for (final path in library.videos ?? <String>[]) { paths[path] = library.rootFolder!; }
    }

    final identities = <String, FileIdentity>{};
    var retry = false;
    for (final path in paths.keys) {
      final identity = await VideoFileIdentity.read(path, cached: cached[byPath[path]?.id]);
      if (identity == null) { retry = true; continue; }
      identities[path] = identity;
    }

    // Only successful scans can establish that a source is missing; offline roots never match.
    final missing = stored.where((video) => roots.contains(video.rootPath)
      && !paths.containsKey(video.videoPath) && !File(video.videoPath!).existsSync()).toList();
    final missingByIdentity = <String, List<Videos>>{};
    final liveByIdentity = <String, List<String>>{};
    String key(FileIdentity identity) => '${identity.size}:${identity.fingerprint}';
    for (final video in missing) {
      final identity = cached[video.id];
      if (identity != null) missingByIdentity.putIfAbsent(key(identity), () => []).add(video);
    }
    for (final entry in identities.entries) {
      liveByIdentity.putIfAbsent(key(entry.value), () => []).add(entry.key);
    }
    final moves = <Map<String, String>>[];
    final movedPaths = <String>{};
    for (final entry in missingByIdentity.entries) {
      final destinations = liveByIdentity[entry.key];
      if (entry.value.length != 1 || destinations == null || destinations.length != 1) continue;
      // An unscanned duplicate makes this match ambiguous too.
      if (stored.any((video) => !roots.contains(video.rootPath)
          && cached[video.id] != null && key(cached[video.id]!) == entry.key)) continue;
      final source = entry.value.single;
      final destination = destinations.single;
      moves.add({
        'id': source.id!, 'oldPath': source.videoPath!, 'newPath': destination, 'newRoot': paths[destination]!,
        if (byPath[destination] != null) 'destinationId': byPath[destination]!.id!,
      });
      movedPaths.add(destination);
    }

    final additions = <Videos>[];
    for (final root in roots) {
      final pending = paths.keys.where((path) => paths[path] == root && identities.containsKey(path)
        && !byPath.containsKey(path) && !movedPaths.contains(path)).toList();
      if (pending.isNotEmpty) additions.addAll(await prepareVideos(Library(rootFolder: root, videos: pending)));
    }
    // Metadata probing and file transfers may outlive the scan. Retry stale plans without writing them.
    for (final entry in identities.entries) {
      if (await VideoFileIdentity.read(entry.key, cached: entry.value) != entry.value) {
        return (added: 0, moved: 0, missing: missing.length, changed: false, retry: true);
      }
    }
    if (moves.any((move) => File(move['oldPath']!).existsSync())) {
      return (added: 0, moved: 0, missing: missing.length, changed: false, retry: true);
    }
    final changed = additions.isNotEmpty || moves.isNotEmpty || snapshots.any((library) {
      final previous = (previousLibraries[library.id]?.videos ?? <String>[]).toSet();
      final current = (library.videos ?? <String>[]).toSet();
      final previousImages = (previousLibraries[library.id]?.images ?? <String>[]).toSet();
      final currentImages = (library.images ?? <String>[]).toSet();
      return previous.length != current.length || !previous.containsAll(current)
        || previousImages.length != currentImages.length || !previousImages.containsAll(currentImages);
    });
    final changedIdentities = Map<String, FileIdentity>.from(identities)..removeWhere((path, identity) =>
      !movedPaths.contains(path) && identity == cached[byPath[path]?.id] && byPath[path]?.rootPath == paths[path]);
    final moved = await DBLibrary.commitScan(snapshots, additions: additions, moves: moves,
      identities: changedIdentities, pathRoots: paths);
    return (added: additions.length, moved: moved, missing: missing.length - moved, changed: changed, retry: retry);
  }
}
