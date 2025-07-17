import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:toastification/toastification.dart';

import 'app/core/app_setting.dart';
import 'app/data/database/db_init.dart';
import 'app/routes/app_pages.dart';
import 'env.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await hotKeyManager.unregisterAll();

  /// local storage
  await GetStorage.init();

  /// app setting
  Get.put<AppSettingService>(AppSettingService(), permanent: true, builder: () => AppSettingService());
  Get.put<DBService>(DBService(), permanent: true, builder: () => DBService());
  await 1.seconds.delay(); // put delay for init all service ~

  runApp(JavIt());
}

class JavIt extends StatelessWidget {
  const JavIt({super.key});

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      // config: ToastificationConfig(),
      child: GetMaterialApp(
        title: Env.appName,
        initialRoute: AppPages.INITIAL,
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
        getPages: AppPages.routes,
        defaultTransition: Transition.fadeIn,
      ),
    );
  }
}
