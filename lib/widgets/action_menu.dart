import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Where the last click landed. Desktop ⋯ menus open beside it, so the
/// menu sits by the button that was pressed without every caller having
/// to pass that button's position. Set by the desktop shell.
Offset? lastPointerDown;

class MenuEntry<T> {
  final T value;
  final String label;
  final IconData icon;
  final Color? color;
  /// Rows sharing a group sit together; a thin rule separates groups.
  final int group;
  /// Small heading over this row's group ("CÔNG CỤ CTV"); set on its first row.
  final String? heading;
  const MenuEntry(this.value, this.label, this.icon, {this.color, this.group = 0, this.heading});
}

/// The desktop ⋯ menu (canvas "Desktop · Menu ⋯"): a small white card by
/// the button — 36px rows, 14px text, 18px icons, groups split by a rule,
/// risky actions last and red. Phones keep their bottom sheets.
Future<T?> showDesktopMenu<T>(BuildContext context, List<MenuEntry<T>> entries, {Offset? at}) {
  final overlay = Overlay.of(context, rootOverlay: true).context.findRenderObject() as RenderBox;
  final size = overlay.size;
  final p = at ?? lastPointerDown ?? size.center(Offset.zero);
  // Clicked in the right half → the menu lines up with the button's right
  // edge; near the bottom Flutter keeps it on screen.
  final position = RelativeRect.fromLTRB(p.dx, p.dy + 14, size.width - p.dx, size.height - p.dy - 14);
  final items = <PopupMenuEntry<T>>[];
  int? lastGroup;
  for (final e in entries) {
    if (lastGroup != null && e.group != lastGroup) items.add(const PopupMenuDivider(height: 11));
    if (e.heading != null && e.group != lastGroup) {
      items.add(PopupMenuItem<T>(enabled: false, height: 28, padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(e.heading!, style: AppText.eyebrow)));
    }
    lastGroup = e.group;
    items.add(PopupMenuItem<T>(
      value: e.value,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(e.icon, size: 18, color: e.color ?? AppColors.textSecondary),
        const SizedBox(width: 12),
        Flexible(child: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: e.color ?? AppColors.text)))),
      ]),
    ));
  }
  return showMenu<T>(
    context: context,
    useRootNavigator: true,
    position: position,
    items: items,
    color: AppColors.bg,
    elevation: 8,
    shadowColor: Colors.black.withValues(alpha: 0.35),
    menuPadding: const EdgeInsets.all(6),
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.border)),
  );
}
