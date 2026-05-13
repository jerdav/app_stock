class AutomaticBackup {
  const AutomaticBackup({
    required this.path,
    required this.name,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final DateTime modifiedAt;
  final int sizeBytes;
}

Future<String?> createDatabaseBackup({
  required String databasePath,
  required String timestamp,
}) async {
  return null;
}

Future<List<AutomaticBackup>> listAutomaticBackups() async {
  return const [];
}

Future<bool> restoreDatabaseBackup({
  required String backupPath,
  required String databasePath,
}) async {
  return false;
}
