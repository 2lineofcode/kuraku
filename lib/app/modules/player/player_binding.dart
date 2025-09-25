import 'package:get/get.dart';

import 'player_controller.dart';

class PlayerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PlayerController>(() => PlayerController());
  }
}
