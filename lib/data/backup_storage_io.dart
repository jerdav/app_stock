import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> createDatabaseBackup({
  required String databasePath,
  required String timestamp,
}) async {
  final dbFile = File(databasePath);
  if (!await dbFile.exists()) {
    return null;
  }

  final appDocDir = await getApplicationDocumentsDirectory();
  final backupDir = Directory('${appDocDir.path}/backups');
  if (!await backupDir.exists()) {
    await backupDir.create(recursive: true);
  }

  final backupFile = File('${backupDir.path}/backup_$timestamp.db');
  await dbFile.copy(backupFile.path);
  await _rotateBackups(backupDir);

  return backupFile.path;
}

Future<bool> restoreDatabaseBackup({
  required String backupPath,
  required String databasePath,
}) async {
  final backupFile = File(backupPath);
  if (!await backupFile.exists()) {
    return false;
  }

  final dbFile = File(databasePath);
  final dbDir = dbFile.parent;
  if (!await dbDir.exists()) {
    await dbDir.create(recursive: true);
  }

  await _deleteIfExists('$databasePath-wal');
  await _deleteIfExists('$databasePath-shm');
  await backupFile.copy(databasePath);
  return true;
}

Future<void> _rotateBackups(Directory backupDir) async {
  final files = await backupDir
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .toList();

  files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

  if (files.length > 28) {
    for (var i = 28; i < files.length; i++) {
      await files[i].delete();
    }
  }
}

Future<void> _deleteIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
