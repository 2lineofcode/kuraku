import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:toastification/toastification.dart';

import 'app/core/app_logging.dart';
import 'app/core/app_setting.dart';
import 'app/data/database/db_init.dart';
import 'app/routes/app_pages.dart';
import 'env.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Stopwatch sw = Stopwatch()..start();

  await hotKeyManager.unregisterAll();

  /// makesure `AppSettingService` already initialized
  await Get.putAsync(() async {
    final service = AppSettingService();
    await service.onReady();
    return service;
  }, permanent: true);

  // makesure `DBService` already initialized
  await Get.putAsync(() async {
    final service = DBService();
    await service.onReady();
    return service;
  }, permanent: true);

  AppLog.logD('App service done in ${sw.elapsedMilliseconds}ms');
  runApp(JavIt());
}

class JavIt extends StatelessWidget {
  const JavIt({super.key});

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: GetMaterialApp(
        enableLog: Env.logLvl == 'debug' ? true : false,
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
