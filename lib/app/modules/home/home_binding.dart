import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/app_pref.dart';
import '../../data/database/_init_db.dart';
import '../../utils/chat_knowledge.dart';
import '../../utils/chat_service.dart';
import '../player/player_controller.dart';
import 'home_controller.dart';
import 'page_chat/page_chat_controller.dart';
import 'page_download/page_download_controller.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_profile/page_profile_controller.dart';
import 'page_search/page_search_controller.dart';
import 'page_settings/page_settings_controller.dart';
import 'page_sqleditor/page_sqleditor_controller.dart';
import 'page_sqleditor/page_sqleditor_tab.dart';
import 'page_tools/page_tools_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    GetInstance().lazyPut<PageSqleditorController>(
        () => PageSqleditorController(
                sources: {
                  'javit.db': Get.find<DBService>().dbMain.path,
                  'r18*.db': Get.find<DBService>().dbR18?.path,
                },
                savedSnippets: AppPref.getSqlSnippets(),
                persistSnippets: AppPref.setSqlSnippets,
                savedTabs: AppPref.getSqlTabs(),
                persistTabs: AppPref.setSqlTabs,
                loadSchema: (source) => PageSqleditorTab.readSchema(
                      source == 'javit.db' ? Get.find<DBService>().dbMain : Get.find<DBService>().dbR18,
                    ),
                createApi: () => ChatService(),
                query: (source, request, token) {
                  final db = Get.find<DBService>();
                  final path = source == 'javit.db' ? db.dbMain.path : db.dbR18?.path;
                  if (path == null) throw StateError('The selected database is unavailable.'.tr);
                  return ChatKnowledge(mainPath: path, loadScript: () => rootBundle.loadString('assets/sql_editor.py')).request(request, token);
                }),
        permanent: true);


    GetInstance().lazyPut<PageChatController>(() => PageChatController(), permanent: true);
    GetInstance().lazyPut<PageProfileController>(() => PageProfileController(), permanent: true);
    // Home pages share the app lifetime, even when first accessed from a dialog.
    GetInstance().lazyPut<PageSettingsController>(() => PageSettingsController(), permanent: true);
    GetInstance().lazyPut<PageToolsController>(() => PageToolsController(), permanent: true);
    GetInstance().lazyPut<PageDownloadController>(() => PageDownloadController(), permanent: true);
    GetInstance().lazyPut<PageExploreController>(() => PageExploreController(), permanent: true);
    GetInstance().lazyPut<PageSearchController>(() => PageSearchController(), permanent: true);
    GetInstance().lazyPut<PageHomeController>(() => PageHomeController(), permanent: true);

    if (!Get.isRegistered<PlayerController>()) {
      Get.put<PlayerController>(PlayerController(), permanent: true);
    }

    Get.lazyPut<HomeController>(() => HomeController());
  }
}
