import 'package:get/get.dart';
import 'package:process_run/process_run.dart' as cmd;

import '../data/database/db_videos.dart';
import '../data/models/videos_entity.dart';
import '../modules/home/page_home/page_home_controller.dart';
import 'helper_toast.dart';

mixin HelperOpener {
  static Future<void> openFolder(String path) async {
    await cmd.run('open -R "$path"').catchError((e) async {
      await HelperToast.error('File does not exist at path: $path');
    });
  }

  static Future<void> openFile(Videos video) async {
    await cmd.run('open "${video.videoPath}"').then((s) async {
      await DBVideos.updateViewCount(video);
      await Get.find<PageHomeController>().getListTop10Watch();
    }).catchError((e) async {
      await HelperToast.error('${e.toString()}');
    });
  }

  static Future<void> openFolderFromFile(String path) async {
    await cmd.run('open -R "$path"').catchError((e)  {
       HelperToast.error('File does not exist at path: $path');
    });
  }
}
