import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/utils/helper_file_picker.dart';

void main() {
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
}
