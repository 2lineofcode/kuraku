import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';

import '../../../data/api/api_javit.dart';
import '../../../data/models/videos_entity.dart';

class PageHomeController extends GetxController {
  final repo = Get.find<ApiJavit>();
  final videos = <Videos>[].obs;
  final category = <VideoCategory>[].obs;
  final actress = <VideoActress>[].obs;

// const kanaKit = KanaKit();

  @override
  Future<void> onInit() async {
    //
    super.onInit();
  }

  Future<void> testt() async {
    Stopwatch stopwatch = Stopwatch()..start();
    // here

    // ...
    stopwatch.stop();
    logI('${stopwatch.elapsedMilliseconds}ms');
  }
}
