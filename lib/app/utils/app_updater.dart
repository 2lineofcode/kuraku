import 'dart:ffi';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppRelease {
  const AppRelease({required this.version, required this.notes, required this.releaseUrl, this.downloadUrl, this.assetName});

  final String version;
  final String notes;
  final Uri releaseUrl;
  final Uri? downloadUrl;
  final String? assetName;
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdater {
  static const _repository = 'https://github.com/2lineofcode/kuraku';
  static final _version = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\+[0-9A-Za-z.-]+)?$');
  static Future<AppRelease?>? _installedCheck;
  static AppRelease? latestRelease;

  static Future<AppRelease?> checkInstalled({Dio? dio}) => _installedCheck ??= _checkInstalled(dio).whenComplete(() => _installedCheck = null);

  static Future<AppRelease?> _checkInstalled(Dio? dio) async {
    PackageInfo info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {
      throw const AppUpdateException('Could not read the installed app version. Please try again.');
    }
    return latestRelease = await check(currentVersion: info.version, dio: dio);
  }

  static Future<AppRelease?> check({required String currentVersion, Dio? dio, Abi? abi}) async {
    final client = dio ?? Dio();
    try {
      final response = await client.get<dynamic>('https://api.github.com/repos/2lineofcode/kuraku/releases/latest', options: Options(
        headers: {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        followRedirects: false,
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      )).timeout(const Duration(seconds: 20), onTimeout: () => throw const AppUpdateException('The update check timed out. Please try again.'));
      final data = response.data;
      if (data is! Map<String, dynamic>) throw const FormatException();
      if (data['draft'] == true || data['prerelease'] == true) return null;
      final tag = data['tag_name'];
      if (tag is! String || !tag.startsWith('v')) throw const FormatException();
      final version = tag.substring(1);
      final latest = _version.firstMatch(version);
      final current = _version.firstMatch(currentVersion);
      if (latest == null || current == null) throw const FormatException();
      var newer = false;
      for (var part = 1; part <= 3; part++) {
        final difference = int.parse(latest[part]!).compareTo(int.parse(current[part]!));
        if (difference == 0) continue;
        newer = difference > 0;
        break;
      }
      if (!newer) return null;
      final releaseUrl = Uri.parse('$_repository/releases/tag/$tag');
      if (data['html_url'] != releaseUrl.toString()) throw const FormatException();
      final notes = data['body'];
      if (notes != null && notes is! String) throw const FormatException();
      final target = abi ?? Abi.current();
      final suffix = target == Abi.macosArm64 ? 'macos-arm64.dmg' : target == Abi.linuxX64 ? 'linux-x64.deb' : target == Abi.windowsX64 ? 'windows-x64.zip' : null;
      final packageName = suffix == null ? null : RegExp('^KuraKu-${RegExp.escape(version.split('+').first)}(?:\\+[0-9]+(?:\\.[0-9]+)?)?-${RegExp.escape(suffix)}\$');
      Uri? downloadUrl;
      String? assetName;
      final assets = data['assets'];
      if (assets is! List) throw const FormatException();
      for (final asset in assets) {
        if (asset is! Map || packageName == null || asset['name'] is! String || !packageName.hasMatch(asset['name'] as String)) continue;
        final name = asset['name'] as String;
        final url = asset['browser_download_url'];
        final uri = url is String ? Uri.tryParse(url) : null;
        if (uri == null || uri.scheme != 'https' || uri.authority != 'github.com' || uri.hasQuery || uri.hasFragment || uri.pathSegments.join('/') != '2lineofcode/kuraku/releases/download/$tag/$name') continue;
        downloadUrl = uri;
        assetName = name;
        break;
      }
      return AppRelease(version: version, notes: notes as String? ?? '', releaseUrl: releaseUrl, downloadUrl: downloadUrl, assetName: assetName);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) throw const AppUpdateException('No app releases are available yet.');
      if (status == 429 || status == 403 && e.response?.headers.value('x-ratelimit-remaining') == '0') {
        throw const AppUpdateException('GitHub rate limit reached. Please try again later.');
      }
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.sendTimeout || e.type == DioExceptionType.receiveTimeout) {
        throw const AppUpdateException('The update check timed out. Please try again.');
      }
      if (e.type == DioExceptionType.connectionError) throw const AppUpdateException('Could not connect to GitHub. Check your internet connection and try again.');
      throw const AppUpdateException('Could not check for updates. Please try again.');
    } on FormatException {
      throw const AppUpdateException('The app release information is invalid.');
    } finally {
      if (dio == null) client.close(force: true);
    }
  }
}
