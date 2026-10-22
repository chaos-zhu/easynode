/// Catalog records arrive separately from the user's saved display order.
/// Append records absent from older layouts so they remain accessible.
List<T> orderTerminalItems<T>(
  Iterable<T> items,
  Iterable<String> orderedIds,
  String Function(T) id,
) {
  final remaining = {for (final item in items) id(item): item};
  final result = <T>[];
  for (final key in orderedIds) {
    final item = remaining.remove(key);
    if (item != null) result.add(item);
  }
  return [...result, ...remaining.values];
}
