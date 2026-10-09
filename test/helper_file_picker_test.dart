import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/utils/helper_file_picker.dart';

void main() {
  test('existingImages preserves order across batches, skips missing files and deduplicates', () async {
    final root = await Directory.systemTemp.createTemp('javit_existing_images_');
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
    final root = await Directory.systemTemp.createTemp('javit_scan_');
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
    final root = await Directory.systemTemp.createTemp('javit_album_');
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
