import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:sqflite/sqflite.dart';

class CallEventDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(CallEvent event) async {
    final db = await _database;
    await db.insert('call_event', event.toJson(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<CallEvent>> getAll() async {
    final db = await _database;
    final maps = await db.query('call_event', orderBy: 'timestamp DESC');
    return maps.map(CallEvent.fromJson).toList();
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await _database;
    await db.update('call_event', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  /// Patches number/contact_name in place (see CallListNotifier.updateCallerInfo).
  Future<void> updateCallerInfo(String id, {String? number, String? contactName}) async {
    final values = <String, Object?>{};
    if (number != null && number.isNotEmpty && number != 'unknown') values['number'] = number;
    if (contactName != null && contactName.isNotEmpty) values['contact_name'] = contactName;
    if (values.isEmpty) return;
    final db = await _database;
    await db.update('call_event', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('call_event', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('call_event');
  }
}
