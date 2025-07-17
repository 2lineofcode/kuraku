import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';

import '../../../models/videos_entity.dart';
import '../../../repository/local/db_r18.dart';
import '../../../repository/network/repo_javit.dart';
import '../../../utils/helper_misc.dart';

class PageHomeController extends GetxController {
  final repo = Get.find<RepoJavit>();
  final videos = <Videos>[].obs;

  @override
  void onInit() {
    //
    super.onInit();
  }

  Future<void> buttonClick() async {
    Stopwatch stopwatch = Stopwatch()..start();

    // here


    // logJson(dataVideo['ssfirst']);
    // logJson(dataVideo['sslast']);
    // logJson(newVideo.toJson());
    // logS(newVideo.category?[0].category);


    // ...
    stopwatch.stop();
    logI('${stopwatch.elapsedMilliseconds}ms');
  }
}
