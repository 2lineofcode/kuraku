import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../utils/helper_file_picker.dart';
import '../../utils/video_file_identity.dart';
import '../models/library_entity.dart';
import '_init_db.dart';
import 'db_library.dart';
import 'db_videos.dart';

enum RelocationStatus { matched, unverified, missing, conflict }
typedef RelocatedVideo = ({String id, String oldPath, String newPath, RelocationStatus status,
  String? reason, FileIdentity? identity});

class LibraryRelocation {
  LibraryRelocation._(this.source, this.destination, List<RelocatedVideo> entries) : entries = List.unmodifiable(entries);

  final Library source, destination;
  final List<RelocatedVideo> entries;
  int count(RelocationStatus status) => entries.where((entry) => entry.status == status).length;
  bool get canApply => count(RelocationStatus.conflict) == 0
    && (entries.isEmpty || count(RelocationStatus.matched) + count(RelocationStatus.unverified) > 0);

  static Future<String> _canonical(String root) async {
    root = p.normalize(p.absolute(root));
    try { return await Directory(root).resolveSymbolicLinks(); }
    on FileSystemException {
      final parent = p.dirname(root);
      return parent == root ? root : p.join(await _canonical(parent), p.basename(root));
    }
  }

  static Future<void> _validateRoots(Library source, String newRoot, List<Library> libraries) async {
    final target = await _canonical(newRoot);
    if (target == await _canonical(source.rootFolder!)) throw StateError('Choose a different root folder.');
    for (final library in libraries) {
      if (library.id == source.id) continue;
      final root = await _canonical(library.rootFolder!);
      if (root == target || p.isWithin(root, target) || p.isWithin(target, root)) {
        throw StateError('The new root overlaps another registered library.');
      }
    }
  }

  static Future<LibraryRelocation> preview(Library library, String newRoot) async {
    if (newRoot.trim().isEmpty || !p.isAbsolute(newRoot)) throw StateError('Select an absolute root folder.');
    final saved = await DBLibrary.getByID(library.id!);
    if (saved.length != 1 || saved.single.rootFolder != library.rootFolder) {
      throw StateError('The library changed. Open a new preview.');
    }
    final source = saved.single;
    newRoot = p.normalize(p.absolute(newRoot));
    await _validateRoots(source, newRoot, await DBLibrary.getAll());
    final scanned = (await HelperFilePicker.scanFolderAndSubFolder(newRoot))!;
    final db = Get.find<DBService>().dbMain;
    final identities = {for (final row in await db.query('video_file_identity')) row['video_id']: (
      size: row['filesize'] as int, modifiedAt: row['modified_at'] as int, fingerprint: row['fingerprint'] as String,
    )};
    final videos = await DBVideos.getAll(includeDeleted: true);
    final byPath = {for (final video in videos) video.videoPath!: video.id};
    final entries = <RelocatedVideo>[];
    for (final video in videos.where((video) => video.rootPath == source.rootFolder)) {
      final oldPath = video.videoPath!;
      final validPath = p.isWithin(source.rootFolder!, oldPath);
      final newPath = validPath ? p.join(newRoot, p.relative(oldPath, from: source.rootFolder!)) : oldPath;
      var status = RelocationStatus.missing;
      String? reason;
      FileIdentity? identity;
      if (!validPath) {
        status = RelocationStatus.conflict;
        reason = 'The stored path is outside the library root.';
      } else if (byPath.containsKey(newPath) && byPath[newPath] != video.id) {
        status = RelocationStatus.conflict;
        reason = 'The destination path is already tracked.';
      } else if (await FileSystemEntity.type(newPath) != FileSystemEntityType.notFound) {
        identity = await VideoFileIdentity.read(newPath);
        final sourceExists = await File(oldPath).exists();
        final original = sourceExists ? await VideoFileIdentity.read(oldPath, cached: identities[video.id]) : identities[video.id];
        if (identity == null || sourceExists && original == null) {
          status = RelocationStatus.conflict;
          reason = 'The file could not be read.';
        } else if (original != null
            ? original.size != identity.size || original.fingerprint != identity.fingerprint
            : (video.filesize ?? 0) > 0 && video.filesize != identity.size) {
          status = RelocationStatus.conflict;
          reason = 'The destination content differs from the original.';
        } else {
          status = original == null ? RelocationStatus.unverified : RelocationStatus.matched;
        }
      }
      entries.add((id: video.id!, oldPath: oldPath, newPath: newPath, status: status, reason: reason, identity: identity));
    }
    entries.sort((a, b) => a.oldPath.compareTo(b.oldPath));
    return LibraryRelocation._(source, scanned, entries);
  }

  Future<void> apply() async {
    if (!canApply) throw StateError('Resolve conflicts and match at least one file before applying.');
    final fresh = await preview(source, destination.rootFolder!);
    if (fresh.entries.length != entries.length || !fresh.canApply
        || Iterable<int>.generate(entries.length).any((index) => fresh.entries[index] != entries[index])) {
      throw StateError('The files changed. Build a new preview before applying.');
    }
    final db = Get.find<DBService>().dbMain;
    await db.transaction((txn) async {
      final libraries = (await txn.query('library')).map((row) => Library.fromJson(row)).toList();
      final current = libraries.where((library) => library.id == source.id).toList();
      if (current.length != 1 || current.single.rootFolder != source.rootFolder) {
        throw StateError('The library changed. Open a new preview.');
      }
      await _validateRoots(current.single, destination.rootFolder!, libraries);
      final stored = await txn.query('videos', where: 'root_path = ?', whereArgs: [source.rootFolder]);
      final paths = {for (final row in stored) row['id']: row['video_path']};
      if (paths.length != entries.length || entries.any((entry) => paths[entry.id] != entry.oldPath)) {
        throw StateError('The library changed. Open a new preview.');
      }
      for (final entry in entries) {
        if (entry.identity != null
            ? await VideoFileIdentity.read(entry.newPath, cached: entry.identity) != entry.identity
            : await FileSystemEntity.type(entry.newPath) != FileSystemEntityType.notFound) {
          throw StateError('The files changed. Build a new preview before applying.');
        }
      }
      final updated = current.single..rootFolder = destination.rootFolder
        ..videos = fresh.destination.videos..subFolder = fresh.destination.subFolder..totalVideo = fresh.destination.totalVideo;
      await DBLibrary.commitScan([updated], executor: txn,
        moves: [for (final entry in entries) {
          'id': entry.id, 'oldPath': entry.oldPath, 'newPath': entry.newPath, 'newRoot': destination.rootFolder!,
        }],
        identities: {for (final entry in entries) if (entry.identity != null) entry.newPath: entry.identity!},
      );
    });
  }
}
