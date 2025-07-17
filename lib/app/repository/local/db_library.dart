import 'package:get/get.dart';

import '../../models/library_entity.dart';
import 'db_init.dart';

mixin DBLibrary {
  static final _db = Get.find<DB>().dbMain;
  static final _tableName = 'Library';

  static Future<bool> _validation(Library library) async {
    final checkRootFolder = await getByRootFolder(library.rootFolder ?? '');
    if (checkRootFolder.isNotEmpty) {
      return false;
    }

    return true;
  }

  static Future<void> add(Library library) async {
    final isOK = await _validation(library);
    if (isOK) await _db.insert(_tableName, library.toJson());
  }

  static Future<void> update(Library library) async {
    await _validation(library);
    await _db.update(_tableName, library.toJson(), where: 'id = ?', whereArgs: [library.id]);
  }

  static Future<void> delete(Library library) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [library.id]);
  }

  static Future<List<Library>> getAll() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return List.generate(maps.length, (index) => Library.fromJson(maps[index]));
  }

  static Future<List<Library>> getByID(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => Library.fromJson(maps[index]));
  }

  static Future<List<Library>> getByRootFolder(String rootFolder) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'root_folder = ?', whereArgs: [rootFolder]);
    return List.generate(maps.length, (index) => Library.fromJson(maps[index]));
  }

  static Future<int> getCount() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return maps.length;
  }
}
