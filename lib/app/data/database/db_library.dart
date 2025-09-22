import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../../utils/helper_toast.dart';
import '../models/library_entity.dart';
import '_init_db.dart';

mixin DBLibrary {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableName = 'library';

  static Future<bool> _validation(Library library) async {
    final isDuplicateRootFolder = await getByRootFolder(library.rootFolder ?? '');
    if (isDuplicateRootFolder.isNotEmpty) return false;

    return true;
  }

  static Future<void> add(Library library) async {
    library.id = UuidV4().generate();
    library.createdAt = DateTime.now().toStringEx();
    library.updatedAt = DateTime.now().toStringEx();
    final isOK = await _validation(library);
    if (isOK) await _db.insert(_tableName, library.toJson());
    else await HelperToast.error('Failed, duplicate root folder');
  }

  static Future<void> update(Library library) async {
    library.updatedAt = DateTime.now().toStringEx();
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

  static Future<void> deleteAll() async => await _db.delete(_tableName);

}
