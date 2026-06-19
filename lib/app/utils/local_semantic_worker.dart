import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../core/app_logging.dart';
import '../core/app_setting.dart';

mixin LocalSemanticWorker {
  static Future<Map<String, String>> extractVisualTags(List<String> imagePaths) async {
    final validPaths = imagePaths.where((item) => item.trim().isNotEmpty).toSet().toList();
    if (validPaths.isEmpty) return <String, String>{};

    final appPath = Get.find<AppSettingService>().appPath;
    final scriptPath = p.join(appPath, 'semantic_worker.py');
    final inputPath = p.join(appPath, 'semantic_worker_input.json');
    final outputPath = p.join(appPath, 'semantic_worker_output.json');

    final inputFile = File(inputPath);
    final outputFile = File(outputPath);

    try {
      await inputFile.writeAsString(
        jsonEncode({'image_paths': validPaths}),
        flush: true,
      );

      final result = await Process.run(
        'python3',
        [scriptPath, 'extract-visual-tags', inputPath, outputPath],
        workingDirectory: appPath,
      );

      if (result.exitCode != 0) {
        AppLog.logW('semantic_worker failed: ${result.stderr}');
        return <String, String>{};
      }

      if (await outputFile.exists() == false) return <String, String>{};

      final raw = await outputFile.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final resultMap = Map<String, dynamic>.from(decoded['result'] ?? {});
      return resultMap.map((key, value) => MapEntry(key, value?.toString() ?? ''));
    } catch (e) {
      AppLog.logW('extractVisualTags failed: $e');
      return <String, String>{};
    } finally {
      try {
        if (await inputFile.exists()) await inputFile.delete();
      } catch (_) {}
      try {
        if (await outputFile.exists()) await outputFile.delete();
      } catch (_) {}
    }
  }
}
