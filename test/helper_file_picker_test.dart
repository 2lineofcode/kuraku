import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/utils/helper_file_picker.dart';

void main() {
  test('supported video paths use the file extension case-insensitively', () {
    for (final extension in ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v']) {
      expect(HelperFilePicker.isSupportedVideoPath('/movies/Video.${extension.toUpperCase()}'), isTrue);
    }
    for (final path in ['mp4', '/movies.mp4/notes', '/movies/video.mp4.txt', '/movies/.mp4', '/movies/video.srt', '']) {
      expect(HelperFilePicker.isSupportedVideoPath(path), isFalse, reason: path);
    }
  });

  test('temporary download paths are recognized in parent folders as well as filenames', () {
    for (final suffix in ['downiepart', 'part', 'tmp', 'crdownload', 'download']) {
      expect(HelperFilePicker.isTemporaryDownloadPath('/movies/Video.$suffix'), isTrue);
      expect(HelperFilePicker.isTemporaryDownloadPath('/movies/Video.${suffix.toUpperCase()}/nested/video.mp4'), isTrue);
    }
    for (final path in ['/movies/JUR-767.mp4', '/movies/downloads/video.mp4', '/movies/downiepart/video.mp4', '/movies/video.downiepart.mp4']) {
      expect(HelperFilePicker.isTemporaryDownloadPath(path), isFalse, reason: path);
    }
  });

  test('scan ignores Downie payloads and images until their download folder is finalized', () async {
    final root = await Directory.systemTemp.createTemp('kuraku_pending_download_');
    addTearDown(() => root.delete(recursive: true));
    final pending = await Directory('${root.path}/JUR-767.downiepart').create();
    final video = File('${pending.path}/FD80D7DE-89A4-4767-A125-CE7F9EEDB245.mp4');
    final handle = await video.open(mode: FileMode.write);
    await handle.truncate(11 * 1024 * 1024);
    await handle.close();
    await File('${pending.path}/cover.jpg').writeAsString('image');
    final before = (await HelperFilePicker.scanFolderAndSubFolder(root.path))!;
    expect(before.videos, isEmpty);
    expect(before.images, isEmpty);
    expect(before.subFolder, isEmpty);
    final finished = await pending.rename('${root.path}/JUR-767');
    final finalPath = '${finished.path}/JUR-767.mp4';
    await File('${finished.path}/${video.uri.pathSegments.last}').rename(finalPath);
    final after = (await HelperFilePicker.scanFolderAndSubFolder(root.path))!;
    expect(after.videos, [finalPath]);
    expect(after.images, ['${finished.path}/cover.jpg']);
    expect(after.totalVideo, 1);
  });

  test('existingImages preserves order across batches, skips missing files and deduplicates', () async {
    final root = await Directory.systemTemp.createTemp('kuraku_existing_images_');
    addTearDown(() => root.delete(recursive: true));
    final paths = <String>[];
    for (var index = 0; index < 35; index++) {
      final file = await File('${root.path}/$index.png').writeAsString('image');
      paths.add(file.path);
    }
    expect(await HelperFilePicker.existingImages([...paths, paths.first, '${root.path}/missing.png']), paths);
    expect(await HelperFilePicker.existingImages(paths, cancelled: () => true), isEmpty);
  });

  test('scanFolderAndSubFolder only includes supported videos over 10 MB', () async {
    final root = await Directory.systemTemp.createTemp('kuraku_scan_');
    addTearDown(() => root.delete(recursive: true));

    final nested = await Directory('${root.path}/nested').create();
    await File('${nested.path}/video.mp4').open(mode: FileMode.write).then((file) async {
      await file.truncate(11 * 1024 * 1024);
      await file.close();
    });
    await File('${nested.path}/small.mkv').writeAsString('small');
    await File('${nested.path}/large.txt').open(mode: FileMode.write).then((file) async {
      await file.truncate(11 * 1024 * 1024);
      await file.close();
    });

    final result = await HelperFilePicker.scanFolderAndSubFolder(root.path);

    expect(result?.subFolder, [nested.path]);
    expect(result?.videos, ['${nested.path}/video.mp4']);
    expect(result?.totalVideo, 1);
  });

  test('scans small images recursively, sorts the album and ignores hidden files', () async {
    final root = await Directory.systemTemp.createTemp('kuraku_album_');
    addTearDown(() => root.delete(recursive: true));
    final nested = await Directory('${root.path}/nested').create();
    final hidden = await Directory('${root.path}/.hidden').create();
    for (final path in ['${root.path}/z.JPG', '${nested.path}/a.png', '${root.path}/.cover.png',
        '${hidden.path}/secret.jpg', '${root.path}/unsupported.raw', '${root.path}/notes.txt']) {
      await File(path).writeAsString('small');
    }
    final result = (await HelperFilePicker.scanFolderAndSubFolder(root.path))!;
    final expected = ['${root.path}/z.JPG', '${nested.path}/a.png']..sort();
    expect(result.images, expected);
    expect(result.videos, isEmpty);
    expect(result.totalVideo, 0);
  });

}
