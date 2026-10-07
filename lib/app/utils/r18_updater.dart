import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../env.g.dart';
import '../core/app_logging.dart';
import '../core/app_setting.dart';
import '../core/app_translations.dart';
import '../data/database/_init_db.dart';
import '../modules/home/page_sqleditor/page_sqleditor_controller.dart';

class R18Updater {
  static final busy = false.obs;
  static final status = ''.obs;
  static final progress = (-1.0).obs;

  static String dateTag(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static Future<({File file, DateTime date})?> findLocalDump(String appPath, int currentVersion) async {
    final files = await Directory(appPath).list(followLinks: false).where((entry) => entry is File).cast<File>().toList();
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final file in files) {
      final match = RegExp(r'^r18dotdev_dump_(\d{4}-\d{2}-\d{2})\.sql(?:\.gz)?$').firstMatch(p.basename(file.path));
      if (match == null) continue;
      final date = DateTime.tryParse(match[1]!);
      if (date == null || dateTag(date) != match[1]) continue;
      if (int.parse(match[1]!.replaceAll('-', '')) <= currentVersion || await file.length() == 0) continue;
      return (file: file, date: date);
    }
    return null;
  }

  static Future<DateTime?> findLatest(Dio dio, String server, int currentVersion, DateTime today) async {
    // ponytail: probe eight weekly releases; use a server manifest if the cadence changes.
    final base = DateTime.utc(2025, 9, 2);
    final day = DateTime.utc(today.year, today.month, today.day);
    final latest = base.add(Duration(days: day.difference(base).inDays ~/ 7 * 7));
    for (var week = 0; week < 8; week++) {
      final date = latest.subtract(Duration(days: week * 7));
      if (int.parse(dateTag(date).replaceAll('-', '')) <= currentVersion) return null;
      try {
        await dio.head('$server/r18dotdev_dump_${dateTag(date)}.sql.gz');
        return date;
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
    }
    if (currentVersion == 0) throw StateError('No R18 dump found in the last 8 weekly releases.');
    return null;
  }

  static Future<int?> update({Future<bool> Function(int version, bool local)? confirm, void Function(String message)? onStatus}) async {
    if (busy.value) return null;
    busy.value = true;
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(minutes: 2)));
    Directory? work;
    File? published;
    File? localSource;
    var activated = false;
    void report(String message, [double value = -1]) {
      status.value = message;
      progress.value = value;
      onStatus?.call(message);
    }
    try {
      report('Checking R18 updates...'.tr);
      final db = Get.find<DBService>();
      final current = await db.dbR18?.getVersion() ?? 0;
      final appPath = Get.find<AppSettingService>().appPath;
      final local = await findLocalDump(appPath, current);
      localSource = local?.file;
      final date = local?.date ?? await findLatest(dio, Env.r18ServerUrl.replaceAll(RegExp(r'/+$'), ''), current, DateTime.now());
      if (date == null) {
        report('R18 is already up to date.'.tr);
        return null;
      }
      final tag = dateTag(date);
      final version = int.parse(tag.replaceAll('-', ''));
      if (confirm != null && !await confirm(version, local != null)) {
        report('');
        return null;
      }
      work = await Directory(appPath).createTemp('.r18-update-');
      final dumpName = 'r18dotdev_dump_$tag.sql.gz';
      final dump = local?.file.path ?? p.join(work.path, dumpName);
      if (local == null) {
        report('Downloading R18...'.tr);
        await dio.download('${Env.r18ServerUrl.replaceAll(RegExp(r'/+$'), '')}/$dumpName', dump, onReceiveProgress: (received, total) {
          final percent = total > 0 ? (received / total).clamp(0.0, 1.0) : -1.0;
          report(total > 0 ? 'Downloading R18 (@{percent}%)...'.trNamed({'percent': '${(percent * 100).round()}'}) : 'Downloading R18...'.tr, percent);
        });
      }
      report('Importing and validating R18...'.tr);
      final name = 'r18_${tag.replaceAll('-', '_')}.db';
      final output = p.join(work.path, name);
      final result = await Process.run('python3', ['-B', '-u', p.join(Get.find<AppSettingService>().bundledAssetsPath, 'r18_database_importer.py'), '--input', dump, '--output', output, if (local != null) '--keep-source']);
      AppLog.logI('R18 import: ${result.stdout}');
      if (result.exitCode != 0) throw ProcessException('python3', [], '${result.stderr}', result.exitCode);
      if (!await File(output).exists() || await File(output).length() == 0) throw StateError('R18 importer produced no database.');
      report('Activating R18 database...'.tr);
      published = await File(output).rename(p.join(appPath, name));
      await db.activateR18Database(published.path, version);
      activated = true;
      try {
        if (Get.isRegistered<PageSqleditorController>() && !Get.isPrepared<PageSqleditorController>()) {
          final editor = Get.find<PageSqleditorController>();
          editor.sources['r18*.db'] = published.path;
          for (final tab in editor.tabs.toList()) {
            if (!tab.isClosed && tab.source.value == 'r18*.db') await tab.refreshSchema();
          }
        }
      } catch (e) {
        AppLog.logW('R18 updated, but SQL schema refresh failed: $e');
      }
      report('R18 updated. Ready to use.'.tr, 1);
      return version;
    } catch (e) {
      AppLog.logE('R18 update failed: $e');
      report('R18 update failed. Please retry.'.tr);
      rethrow;
    } finally {
      dio.close();
      try {
        if (!activated && published != null && await published.exists()) await published.delete();
        if (work != null && await work.exists()) await work.delete(recursive: true);
        if (activated && localSource != null && await localSource.exists()) await localSource.delete();
      } catch (e) {
        AppLog.logW('Could not clean up R18 update files: $e');
      }
      busy.value = false;
    }
  }
}
