/// The server's `/server-list-config`, shared with Web.
class ServerListConfig {
  const ServerListConfig({
    this.columnSettings = defaultColumns,
    this.displayMode = 'group',
  });

  static const defaultColumns = <String, bool>{
    'selection': true,
    'name': true,
    'username': true,
    'host': true,
    'port': true,
    'authType': true,
    'proxyType': false,
    'expired': false,
    'consoleUrl': false,
    'tag': true,
  };

  final Map<String, bool> columnSettings;
  final String displayMode;

  bool shows(String column) =>
      columnSettings[column] ?? defaultColumns[column] ?? false;

  factory ServerListConfig.fromJson(Map<String, dynamic> json) {
    final columns = json['columnSettings'];
    return ServerListConfig(
      columnSettings: Map.unmodifiable({
        ...defaultColumns,
        if (columns is Map)
          for (final entry in columns.entries)
            if (entry.key is String &&
                entry.value is bool &&
                entry.key != 'index')
              entry.key as String: entry.value as bool,
      }),
      displayMode: json['displayMode'] == 'list' ? 'list' : 'group',
    );
  }

  ServerListConfig withColumn(String column, bool visible) => ServerListConfig(
    columnSettings: Map.unmodifiable({...columnSettings, column: visible}),
    displayMode: displayMode,
  );

  ServerListConfig withDisplayMode(String mode) =>
      ServerListConfig(columnSettings: columnSettings, displayMode: mode);

  Map<String, dynamic> toJson() => {
    'columnSettings': columnSettings,
    'displayMode': displayMode,
  };
}
