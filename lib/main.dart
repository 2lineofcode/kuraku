import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'app/core/app_setting.dart';
import 'app/repository/local/db_init.dart';
import 'app/routes/app_pages.dart';
import 'env.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// local storage
  await GetStorage.init();

  /// app setting
  Get.put(AppSettingService());
  Get.put(DB());
  await 300.milliseconds.delay(); // put delay for init `AppSettingService`

  runApp(JavIt());
}

class JavIt extends StatelessWidget {
  const JavIt({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: Env.appName,
      initialRoute: AppPages.INITIAL,
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      getPages: AppPages.routes,
      defaultTransition: Transition.fadeIn,
    );
  }
}
