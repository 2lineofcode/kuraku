import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../models/library_entity.dart';
import '_init_db.dart';
import 'db_library.dart';

enum LibraryHealthStatus { offlineDrive, missingFile, incompleteMetadata, unreadableFile }
typedef LibraryHealthIssue = ({LibraryHealthStatus status, String path, List<String> details});

class LibraryHealthCheck {
  static Future<List<LibraryHealthIssue>> run() async {
    final libraries = await DBLibrary.getAll();
    final rows = await Get.find<DBService>().dbMain.query('videos',
      columns: ['root_path', 'video_path', 'video_code', 'title', 'poster', 'release_date', 'duration', 'actress', 'category'],
      where: 'is_deleted = 0');
    return inspect(libraries, rows);
  }

  static Future<Set<String>> _mountedRoots() async {
    if (Platform.isWindows) return {};
    final result = await Process.run(Platform.isMacOS ? '/sbin/mount' : 'mount', []);
    if (result.exitCode != 0) throw FileSystemException('Could not read mounted drives');
    return RegExp(r' on (.*?) (?:\(|type )').allMatches('${result.stdout}')
      .map((match) => match[1]!.replaceAll(r'\040', ' ')).toSet();
  }

  static String? _driveRoot(String path) {
    if (Platform.isWindows) {
      final root = p.rootPrefix(path);
      return root.isEmpty ? null : root;
    }
    // ponytail: Unix drive detection follows standard mount paths; custom mount points need persisted mount identities.
    final parts = p.split(path);
    if (path.startsWith('/Volumes/') || path.startsWith('/mnt/')) {
      return parts.length > 2 ? p.join(parts[0], parts[1], parts[2]) : null;
    }
    if (path.startsWith('/media/')) {
      return parts.length > 3 ? p.joinAll(parts.take(4)) : path;
    }
    return null;
  }

  static bool _blank(Object? value) => value == null || '$value'.trim().isEmpty || '$value'.trim() == 'null';

  static List<String> _missingMetadata(Map<String, Object?> row) {
    final fields = <String>[
      for (final field in ['video_code', 'title', 'poster', 'release_date'])
        if (_blank(row[field])) field,
      if (row['duration'] is! num || (row['duration'] as num) <= 0) 'duration',
    ];
    for (final field in ['actress', 'category']) {
      try {
        final values = jsonDecode('${row[field]}');
        final name = field == 'actress' ? 'name_romaji' : 'category';
        if (values is! List || values.isEmpty || values.any((value) => value is! Map || _blank(value[name]))) {
          fields.add(field);
        }
      } on FormatException {
        fields.add(field);
      }
    }
    return fields;
  }

  static Future<List<LibraryHealthIssue>> inspect(List<Library> libraries, List<Map<String, Object?>> rows,
      {Set<String>? mountedRoots}) async {
    final mounts = mountedRoots ?? await _mountedRoots();
    final issues = <LibraryHealthIssue>[];
    final offline = <String>{};
    Future<bool> isOffline(String path) async {
      final drive = _driveRoot(path);
      if (drive == null) return false;
      var connected = mounts.any((mount) => mount != '/' && (mount == path || p.isWithin(mount, path)));
      if (Platform.isWindows) {
        try {
          await Directory(drive).list().take(1).drain<void>();
          connected = true;
        } on FileSystemException catch (e) {
          connected = !_missing(e) && ![21, 53, 67, 1167].contains(e.osError?.errorCode);
        }
      } else if (!connected) {
        try {
          final resolved = await Directory(drive).resolveSymbolicLinks();
          connected = resolved != drive && _driveRoot(resolved) == null;
        } on FileSystemException {
          // A stale mount directory does not prove the drive is connected.
        }
      }
      if (connected) return false;
      if (offline.add(drive)) issues.add((status: LibraryHealthStatus.offlineDrive, path: drive, details: []));
      return true;
    }

    for (final library in libraries) {
      final root = library.rootFolder ?? '';
      if (await isOffline(root)) continue;
      try {
        // Listing catches inaccessible roots even when stat succeeds.
        if (root.isEmpty) throw FileSystemException('Missing path', root, const OSError('', 2));
        await Directory(root).list().take(1).drain<void>();
      } on FileSystemException catch (e) {
        issues.add((status: _missing(e) ? LibraryHealthStatus.missingFile : LibraryHealthStatus.unreadableFile,
          path: root, details: ['Library folder']));
      }
    }
    for (final row in rows) {
      final path = '${row['video_path'] ?? ''}';
      final fields = _missingMetadata(row);
      if (fields.isNotEmpty) issues.add((status: LibraryHealthStatus.incompleteMetadata, path: path, details: fields));
      if (await isOffline(path.isEmpty ? '${row['root_path'] ?? ''}' : path)) continue;
      RandomAccessFile? file;
      try {
        if (path.isEmpty) throw FileSystemException('Missing path', path, const OSError('', 2));
        file = await File(path).open();
        if (await file.length() == 0) throw FileSystemException('Empty file', path);
        if ((await file.read(1)).isEmpty) throw FileSystemException('Empty file', path);
      } on FileSystemException catch (e) {
        issues.add((status: _missing(e) ? LibraryHealthStatus.missingFile : LibraryHealthStatus.unreadableFile,
          path: path, details: []));
      } finally {
        await file?.close();
      }
    }
    // Recheck mounts so a drive disconnected during the scan is not reported as missing.
    if (mountedRoots == null && !Platform.isWindows) {
      mounts.clear();
      mounts.addAll(await _mountedRoots());
      for (final issue in List.of(issues)) {
        if ((issue.status == LibraryHealthStatus.missingFile || issue.status == LibraryHealthStatus.unreadableFile)
            && await isOffline(issue.path)) issues.remove(issue);
      }
    }
    return issues;
  }

  static bool _missing(FileSystemException error) => error.osError?.errorCode == 2
    || Platform.isWindows && error.osError?.errorCode == 3;
}
