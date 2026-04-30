import 'package:get/get.dart';

import '../modules/home/home_binding.dart';
import '../modules/home/home_view.dart';
import '../modules/img_viewer/img_viewer_binding.dart';
import '../modules/img_viewer/img_viewer_view.dart';
import '../modules/player/player_binding.dart';
import '../modules/player/player_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.HOME;

  static final routes = [
    GetPage(
      name: Routes.HOME,
      page: () => const HomeView(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: Routes.PLAYER,
      page: () => const PlayerView(),
      binding: PlayerBinding(),
    ),
    GetPage(
      name: Routes.IMG_VIEWER,
      page: () => const ImgViewerView(),
      binding: ImgViewerBinding(),
    ),
  ];
}
