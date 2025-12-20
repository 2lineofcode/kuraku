import 'package:get/get.dart';

import 'player_controller.dart';

class PlayerBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<PlayerController>()) {
      Get.put<PlayerController>(PlayerController(), permanent: true);
    }
  }
}
