import 'package:get/get.dart';

import 'img_viewer_controller.dart';

class ImgViewerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ImgViewerController>(
      () => ImgViewerController(),
    );
  }
}
