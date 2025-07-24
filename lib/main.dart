import 'package:fast_cached_network_image/fast_cached_network_image.dart';
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

  await FastCachedImageConfig.init(clearCacheAfter: 365.days);

  // local storage
  await GetStorage.init(Env.appName);

  /// makesure `AppSettingService` already initialized
  await Get.putAsync(() async {
    final service = AppSettingService();
    await service.onInit();
    return service;
  }, permanent: true);

  // makesure `DBService` already initialized
  await Get.putAsync(() async {
    final service = DBService();
    await service.onInit();
    return service;
  }, permanent: true);

  runApp(JavIt());
}

class JavIt extends StatelessWidget {
  const JavIt({super.key});

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
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
