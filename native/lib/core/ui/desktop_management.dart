import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_result.dart';
import 'app_color_theme.dart';
import 'app_dialog.dart';
import 'desktop_form_controls.dart';
import 'desktop_management_dialog.dart';
import 'desktop_popover.dart';
import 'desktop_select.dart';

// Desktop management pages share the Web table, form and button dimensions.
String mx(BuildContext context, String zh, String en) =>
    AppLocalizations.of(context).locale.languageCode == 'zh' ? zh : en;

String managementError(Object error) =>
    error is ApiFailure ? error.message : error.toString();

String managementDate(DateTime? date) => date == null
    ? '—'
    : DateFormat('yyyy-MM-dd HH:mm:ss').format(date.toLocal());

Future<T?> showManagementDrawer<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondary) => themes.wrap(
      Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: math.min(
            MediaQuery.sizeOf(context).width,
            math.max(500, MediaQuery.sizeOf(context).width * .72),
          ),
          child: Material(
            color: context.colors.card,
            child: SafeArea(child: builder(context)),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
  );
}

void managementNotice(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> managementConfirm(BuildContext context, String message) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => DesktopManagementDialog(
        width: 440,
        title: mx(context, '确认操作', 'Confirm'),
        body: Text(message, style: const TextStyle(fontSize: 14, height: 1.6)),
        actions: [
          ManagementButton(
            label: mx(context, '取消', 'Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ManagementButton(
            label: mx(context, '确定', 'Confirm'),
            primary: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ==
    true;

class ManagementPage extends StatelessWidget {
  const ManagementPage({
    super.key,
    required this.toolbar,
    required this.child,
    this.footer,
    this.error,
    this.busy = false,
    this.tableSpacing = 16,
  });
  final Widget toolbar, child;
  final Widget? footer;
  final String? error;
  final bool busy;
  final double tableSpacing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.colors.border)),
          ),
          alignment: Alignment.centerLeft,
          child: toolbar,
        ),
        SizedBox(height: tableSpacing),
        if (error != null) ManagementError(message: error!),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: child),
              if (busy)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
        if (footer != null)
          Padding(padding: const EdgeInsets.only(top: 14), child: footer!),
      ],
    ),
  );
}

/// Web-style line tabs: hover changes text color without a Material fill.
class ManagementTabs<T extends Object> extends StatelessWidget {
  const ManagementTabs({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.height = 32,
    this.horizontalPadding = 20,
    this.fontWeight = FontWeight.w500,
    this.icons = const {},
    this.inset = 0,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final double height, horizontalPadding;
  final FontWeight fontWeight;
  final Map<T, IconData> icons;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Row(
          children: [
            for (final (index, entry) in options.entries.indexed)
              Semantics(
                selected: value == entry.key,
                child: Stack(
                  children: [
                    TextButton(
                      onPressed: onChanged == null
                          ? null
                          : () => onChanged!(entry.key),
                      style: ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(Size(0, height)),
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.fromLTRB(
                            index == 0 ? 0 : horizontalPadding,
                            6,
                            index == options.length - 1 ? 0 : horizontalPadding,
                            6,
                          ),
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        splashFactory: NoSplash.splashFactory,
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        backgroundColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.disabled)
                              ? colors.softMuted
                              : value == entry.key ||
                                    states.contains(WidgetState.hovered) ||
                                    states.contains(WidgetState.focused)
                              ? colors.accent
                              : colors.text,
                        ),
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(fontSize: 14, fontWeight: fontWeight),
                        ),
                        shape: WidgetStateProperty.resolveWith(
                          (states) => RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(3),
                            side: states.contains(WidgetState.focused)
                                ? BorderSide(color: colors.accent)
                                : BorderSide.none,
                          ),
                        ),
                        animationDuration:
                            MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icons[entry.key] != null) ...[
                            Icon(icons[entry.key], size: 15),
                            const SizedBox(width: 7),
                          ],
                          Text(entry.value),
                        ],
                      ),
                    ),
                    if (value == entry.key)
                      Positioned(
                        left: index == 0 ? 0 : horizontalPadding,
                        right: index == options.length - 1
                            ? 0
                            : horizontalPadding,
                        bottom: 0,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: colors.accent,
                            child: const SizedBox(height: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ManagementButton extends StatelessWidget {
  const ManagementButton({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.danger = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary, danger;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: !danger
        ? desktopButtonStyle(context, primary: primary)
        : desktopButtonStyle(context).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? context.colors.softMuted
                  : context.colors.danger,
            ),
            backgroundColor: WidgetStatePropertyAll(
              context.colors.danger.withValues(alpha: .08),
            ),
            side: WidgetStatePropertyAll(
              BorderSide(color: context.colors.danger.withValues(alpha: .4)),
            ),
            overlayColor: WidgetStatePropertyAll(
              context.colors.danger.withValues(alpha: .12),
            ),
          ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    ),
  );
}

class ManagementLink extends StatelessWidget {
  const ManagementLink({
    super.key,
    required this.label,
    this.onPressed,
    this.danger = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: danger ? context.colors.danger : context.colors.accent,
      textStyle: const TextStyle(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    child: Text(label),
  );
}

class ManagementField extends StatelessWidget {
  const ManagementField({
    super.key,
    required this.label,
    required this.child,
    this.bottomSpacing = 16,
  });
  final String label;
  final Widget child;
  final double bottomSpacing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottomSpacing),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.colors.text,
          ),
        ),
        const SizedBox(height: 7),
        child,
      ],
    ),
  );
}

class ManagementPair extends StatelessWidget {
  const ManagementPair({super.key, required this.left, required this.right});
  final Widget left, right;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => size.maxWidth < 390
        ? Column(children: [left, right])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              Expanded(child: right),
            ],
          ),
  );
}

class ManagementError extends StatelessWidget {
  const ManagementError({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: context.colors.dangerSoft,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: context.colors.danger, fontSize: 13),
          ),
        ),
        if (onRetry != null)
          ManagementLink(label: mx(context, '重试', 'Retry'), onPressed: onRetry),
      ],
    ),
  );
}

class ManagementTag extends StatelessWidget {
  const ManagementTag(this.label, {super.key, this.color, this.round = false});
  final String label;
  final Color? color;
  final bool round;
  @override
  Widget build(BuildContext context) {
    final tone = color ?? context.colors.accent;
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .08),
          border: Border.all(color: tone.withValues(alpha: .25)),
          borderRadius: BorderRadius.circular(round ? 999 : 4),
        ),
        child: Text(label, style: TextStyle(color: tone, fontSize: 12)),
      ),
    );
  }
}

class ManagementSwitch extends StatelessWidget {
  const ManagementSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: label,
    child: TextButton(
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onChanged == null ? .5 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? context.colors.accent : context.colors.strongBorder,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ManagementColumn {
  const ManagementColumn(this.label, {this.width = 160, this.heading})
    : fixedRight = false;
  const ManagementColumn.actions(this.label, {this.width = 140})
    : heading = null,
      fixedRight = true;

  final String label;
  final double width;
  final Widget? heading;
  final bool fixedRight;
}

/// A single scroll surface keeps variable-height rows, expansions and the
/// header aligned. Action cells follow the viewport's right edge.
class ManagementTable extends StatefulWidget {
  const ManagementTable({
    super.key,
    required this.columns,
    required this.rows,
    this.empty,
    this.expanded = const {},
    this.onRowTap,
    this.bordered = true,
  });
  final List<ManagementColumn> columns;
  final List<List<Widget>> rows;
  final Map<int, Widget> expanded;
  final String? empty;
  final ValueChanged<int>? onRowTap;
  final bool bordered;

  @override
  State<ManagementTable> createState() => _ManagementTableState();
}

class _ManagementTableState extends State<ManagementTable> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = context.colors;
      final columns = widget.columns;
      final scale = math.max(
        1.0,
        MediaQuery.textScalerOf(context).scale(13) / 13,
      );
      final base = columns.fold<double>(0, (sum, c) => sum + c.width * scale);
      final width = math.max(base, constraints.maxWidth);
      final flexibleIndex = columns.first.width < 80 && columns.length > 1
          ? 1
          : 0;
      final fixed = columns.last.fixedRight;
      Widget line(
        List<Widget> cells, {
        bool header = false,
        bool hovered = false,
      }) {
        final background = header || hovered ? colors.chip : colors.card;
        return Container(
          constraints: BoxConstraints(minHeight: header ? 44 : 48),
          decoration: BoxDecoration(
            color: background,
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: .65)),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columns.length; i++)
                  if (fixed && i == columns.length - 1)
                    AnimatedBuilder(
                      animation: _horizontal,
                      child: _cell(
                        columns[i],
                        cells[i],
                        columns[i].width * scale,
                        header: header,
                      ),
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                          (_horizontal.hasClients ? _horizontal.offset : 0) +
                              constraints.maxWidth -
                              width,
                          0,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: background,
                            boxShadow: width > constraints.maxWidth
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .08,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(-3, 0),
                                    ),
                                  ]
                                : null,
                          ),
                          child: child,
                        ),
                      ),
                    )
                  else
                    _cell(
                      columns[i],
                      cells[i],
                      columns[i].width * scale +
                          (i == flexibleIndex ? width - base : 0),
                      header: header,
                    ),
              ],
            ),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          border: widget.bordered ? Border.all(color: colors.border) : null,
          borderRadius: BorderRadius.circular(widget.bordered ? 10 : 0),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                line([
                  for (final c in columns) c.heading ?? Text(c.label),
                ], header: true),
                Expanded(
                  child: widget.rows.isEmpty
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: 120,
                            child: Center(
                              child: Text(
                                widget.empty ?? mx(context, '暂无数据', 'No data'),
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: widget.rows.length,
                          itemBuilder: (context, index) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ManagementHoverRow(
                                onTap: widget.onRowTap == null
                                    ? null
                                    : () => widget.onRowTap!(index),
                                builder: (hovered) =>
                                    line(widget.rows[index], hovered: hovered),
                              ),
                              if (widget.expanded[index] != null)
                                widget.expanded[index]!,
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _cell(
    ManagementColumn column,
    Widget child,
    double width, {
    required bool header,
  }) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: header ? context.colors.muted : context.colors.text,
          fontWeight: header ? FontWeight.w600 : FontWeight.w400,
        ),
        child: Align(
          alignment: column.fixedRight
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: column.fixedRight ? IntrinsicWidth(child: child) : child,
        ),
      ),
    ),
  );
}

class ManagementPagination extends StatelessWidget {
  const ManagementPagination({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
  });
  final int total, page, pageSize;
  final ValueChanged<int> onPage, onPageSize;
  @override
  Widget build(BuildContext context) {
    final last = math.max(1, (total / pageSize).ceil());
    final current = page.clamp(1, last);
    final pages = <int>{
      1,
      last,
      if (last <= 7)
        ...List.generate(last, (i) => i + 1)
      else if (current <= 4) ...[
        2,
        3,
        4,
        5,
      ] else if (current >= last - 3) ...[
        last - 4,
        last - 3,
        last - 2,
        last - 1,
      ] else ...[
        current - 1,
        current,
        current + 1,
      ],
    }.toList()..sort();
    Widget button({
      required Widget child,
      required String label,
      VoidCallback? onPressed,
      bool selected = false,
    }) => Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? context.colors.accent
              : context.colors.text,
          disabledForegroundColor: context.colors.softMuted,
          minimumSize: const Size(32, 32),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          splashFactory: NoSplash.splashFactory,
          textStyle: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Tooltip(message: label, child: child),
      ),
    );
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            mx(context, '共 $total 条', '$total total'),
            style: TextStyle(color: context.colors.muted, fontSize: 13),
          ),
          SizedBox(
            width: 116,
            child: DesktopSelect(
              controlHeight: 32,
              options: {
                for (final s in [20, 50, 100])
                  '$s': mx(context, '$s 条/页', '$s / page'),
              },
              values: ['$pageSize'],
              onSelected: (v) => onPageSize(int.parse(v)),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(
                label: mx(context, '上一页', 'Previous page'),
                onPressed: current > 1 ? () => onPage(current - 1) : null,
                child: const Icon(Icons.chevron_left, size: 16),
              ),
              for (var i = 0; i < pages.length; i++) ...[
                if (i > 0 && pages[i] - pages[i - 1] > 1)
                  button(
                    label: pages[i] < current
                        ? mx(context, '向前 5 页', 'Previous 5 pages')
                        : mx(context, '向后 5 页', 'Next 5 pages'),
                    onPressed: () => onPage(
                      (current + (pages[i] < current ? -5 : 5)).clamp(1, last),
                    ),
                    child: const Text('…'),
                  ),
                button(
                  label: mx(context, '第 ${pages[i]} 页', 'Page ${pages[i]}'),
                  selected: pages[i] == current,
                  onPressed: () {
                    if (pages[i] != current) onPage(pages[i]);
                  },
                  child: Text('${pages[i]}'),
                ),
              ],
              button(
                label: mx(context, '下一页', 'Next page'),
                onPressed: current < last ? () => onPage(current + 1) : null,
                child: const Icon(Icons.chevron_right, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManagementHoverRow extends StatefulWidget {
  const _ManagementHoverRow({required this.builder, this.onTap});
  final Widget Function(bool hovered) builder;
  final VoidCallback? onTap;
  @override
  State<_ManagementHoverRow> createState() => _ManagementHoverRowState();
}

class _ManagementHoverRowState extends State<_ManagementHoverRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: widget.builder(_hovered),
    ),
  );
}

/// Editable select for Web's allow-create fields (Cron, timezone and API URL).
class ManagementSuggestionInput extends StatelessWidget {
  const ManagementSuggestionInput({
    super.key,
    required this.controller,
    required this.options,
    this.validator,
    this.hint,
    this.enabled = true,
    this.controlHeight = desktopFormControlHeight,
  });
  final TextEditingController controller;
  final Map<String, String> options;
  final String? Function(String?)? validator;
  final String? hint;
  final bool enabled;
  final double controlHeight;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      autocorrect: false,
      style: const TextStyle(fontSize: 13),
      decoration:
          desktopInputDecoration(
            context,
            hint: hint,
            controlHeight: controlHeight,
          ).copyWith(
            suffixIconConstraints: BoxConstraints(
              minWidth: 36,
              minHeight: controlHeight,
            ),
            suffixIcon: IconButton(
              tooltip: mx(context, '选择预设', 'Choose preset'),
              constraints: BoxConstraints.tightFor(
                width: 36,
                height: controlHeight,
              ),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.keyboard_arrow_down, size: 17),
              onPressed: !enabled
                  ? null
                  : () async {
                      final selected = await showDesktopPopover<String>(
                        context: anchor,
                        builder: (context) => SingleChildScrollView(
                          padding: const EdgeInsets.all(5),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final option in options.entries)
                                TextButton(
                                  style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    foregroundColor:
                                        controller.text == option.key
                                        ? context.colors.accent
                                        : context.colors.text,
                                    textStyle: const TextStyle(fontSize: 13),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  onPressed: () =>
                                      Navigator.pop(context, option.key),
                                  child: Text(option.value),
                                ),
                            ],
                          ),
                        ),
                      );
                      if (selected != null && anchor.mounted) {
                        controller.text = selected;
                      }
                    },
            ),
          ),
    ),
  );
}

class ManagementChoices extends StatelessWidget {
  const ManagementChoices({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final Map<String, String> options;
  final String value;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 4,
    children: [
      for (final option in options.entries)
        Semantics(
          checked: value == option.key,
          inMutuallyExclusiveGroup: true,
          child: TextButton(
            onPressed: onChanged == null ? null : () => onChanged!(option.key),
            style: TextButton.styleFrom(
              foregroundColor: value == option.key
                  ? context.colors.accent
                  : context.colors.text,
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  value == option.key
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Text(option.value, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
    ],
  );
}

/// Live output follows new data until the user scrolls away from the bottom.
class ManagementOutput extends StatefulWidget {
  const ManagementOutput({super.key, required this.text});
  final String text;
  @override
  State<ManagementOutput> createState() => _ManagementOutputState();
}

class _ManagementOutputState extends State<ManagementOutput> {
  final _scroll = ScrollController();
  bool _follow = true;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
    _scrollToEnd();
  }

  void _scrolled() {
    if (_scroll.hasClients) _follow = _scroll.position.extentAfter < 28;
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _follow && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });
  @override
  void didUpdateWidget(ManagementOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) _scrollToEnd();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    child: SelectableText(
      widget.text,
      style: TextStyle(
        fontSize: 13,
        height: 1.6,
        fontFamily: 'monospace',
        color: context.colors.text,
      ),
    ),
  );
}
