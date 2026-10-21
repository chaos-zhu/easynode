import '../order/order_layout.dart';

/// Local edits only. Indices use Flutter's normalized `onReorderItem` contract.
class DesktopServerOrderDraft {
  DesktopServerOrderDraft(OrderLayout layout)
    : revision = layout.revision,
      groups = layout.sections.map((section) => section.groupId).toList(),
      items = {
        for (final section in layout.sections)
          section.groupId: [...section.itemIds],
      },
      flat = [...layout.flatItemIds];

  final int revision;
  final List<String> groups;
  final Map<String, List<String>> items;
  final List<String> flat;

  static void move(List<String> ids, int oldIndex, int newIndex) {
    ids.insert(newIndex, ids.removeAt(oldIndex));
  }

  List<OrderChange> instanceChanges({required bool grouped}) => grouped
      ? [
          for (final id in groups)
            OrderChange(
              scope: 'groupItems',
              groupId: id,
              orderedIds: [...items[id]!],
            ),
        ]
      : [
          OrderChange(scope: 'flat', orderedIds: [...flat]),
        ];
}
