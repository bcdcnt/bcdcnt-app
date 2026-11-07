import '../services/imgcdn.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/friendly_error.dart';
import 'shimmer.dart' show SongListSkeleton;

// Shared building blocks of the 2026-11 brand redesign (white + #711313 +
// #B48988, Montserrat). Screens compose these so headers, chips, buttons and
// skeletons look the same everywhere.

/// Brand "gradient map" for archive photos (guideline, Trường hợp 1): keeps
/// the photo's light and shade but colours it in the logo's red, so faded,
/// black-and-white and modern pictures read as one set.
class BrandTint extends StatelessWidget {
  final Widget child;
  final bool enabled;
  const BrandTint({super.key, required this.child, this.enabled = true});

  // Duotone: shadows go deep wine, highlights warm paper, so photos read
  // as old prints. A flat BlendMode.color with the logo red turned every
  // picture salmon-pink.
  static const _dark = [46.0, 8.0, 10.0];
  static const _light = [246.0, 232.0, 222.0];
  static final _filter = ColorFilter.matrix(<double>[
    for (var c = 0; c < 3; c++) ...[
      (_light[c] - _dark[c]) / 255 * 0.2126,
      (_light[c] - _dark[c]) / 255 * 0.7152,
      (_light[c] - _dark[c]) / 255 * 0.0722,
      0,
      _dark[c],
    ],
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    // ClipRect bounds the filter layer: on Impeller (iOS) an unclipped
    // ColorFiltered spills the tint over everything painted below it.
    return ClipRect(child: ColorFiltered(colorFilter: _filter, child: child));
  }
}

/// Network image with a soft placeholder; [tint] applies [BrandTint].
class NetImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final double radius;
  final bool tint;
  final bool circle;
  final Widget? fallback;
  /// Read by screen readers; without it the picture is treated as
  /// decoration (the caption next to it already says what it is).
  final String? semanticLabel;
  const NetImage({super.key, required this.url, this.width, this.height, this.radius = 0, this.tint = false, this.circle = false, this.fallback, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final ph = Container(width: width, height: height, color: AppColors.surfaceLight);
    Widget img = (url == null || url!.isEmpty)
        ? (fallback ?? ph)
        : CachedNetworkImage(
            imageUrl: cdnImg(url!, (width != null && width!.isFinite ? width! : 400) * 2.5),
            width: width,
            height: height,
            fit: BoxFit.cover,
            memCacheWidth: width != null && width!.isFinite ? (width! * 3).round() : 900,
            // Tint only the loaded photo: tinting the grey placeholder or the
            // initials fallback turned them into blank pink discs.
            imageBuilder: tint
                ? (_, provider) => BrandTint(child: Image(image: provider, width: width, height: height, fit: BoxFit.cover))
                : null,
            placeholder: (_, __) => ph,
            errorWidget: (_, __, ___) => fallback ?? ph,
          );
    if (circle) {
      img = ClipOval(child: img);
    } else if (radius > 0) {
      img = ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
    }
    return semanticLabel == null ? ExcludeSemantics(child: img) : Semantics(image: true, label: semanticLabel, child: ExcludeSemantics(child: img));
  }
}

/// "Tên mục" row: 20/800 title, optional red "Xem tất cả" link.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;
  const SectionTitle(this.title, {super.key, this.action = 'Xem tất cả', this.onAction, this.padding = const EdgeInsets.fromLTRB(20, 28, 12, 10)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title, style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (onAction != null && action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 8), foregroundColor: AppColors.accentLight),
                child: Text(action!, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
              ),
          ],
        ),
      );
}

/// Large page title used at the top of tab screens ("Khám phá", "Thư viện").
class PageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  const PageTitle(this.title, {super.key, this.subtitle, this.actions = const [], this.leading});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: display(TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15, color: AppColors.text))),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  ],
                ],
              ),
            ),
            ...actions,
          ],
        ),
      );
}

/// 44px round icon button on a soft surface (header actions).
class RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool dot;
  final Color? background;
  final Color? color;
  const RoundIcon({super.key, required this.icon, required this.tooltip, this.onTap, this.dot = false, this.background, this.color});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: dot ? '$tooltip, có mục mới' : tooltip,
          child: Material(
            color: background ?? AppColors.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap!();
                    },
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 22, color: color ?? AppColors.text),
                    if (dot)
                      Positioned(
                        top: 10,
                        right: 11,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle, border: Border.all(color: background ?? AppColors.surface, width: 2)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Pill chip; selected = ink on bg (black pill on white, white on dark).
class BrandChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  /// Soft red variant ("Đang được tìm").
  final bool soft;
  const BrandChip({super.key, required this.label, this.selected = false, this.onTap, this.icon, this.soft = false});

  @override
  Widget build(BuildContext context) {
    // Selected = brand wine (black chips were the heaviest mark on screen).
    final bg = selected ? (AppColors.isLight ? AppColors.wine : AppColors.accent) : (soft ? AppColors.accentSoft : AppColors.surface);
    final fg = selected ? Colors.white : (soft ? AppColors.accentLight : AppColors.textSecondary);
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          // 44pt: Apple's minimum touch target; these are the main filters.
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg))),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// Horizontal strip of [BrandChip]s.
class ChipStrip extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final EdgeInsets padding;
  const ChipStrip({super.key, required this.labels, required this.selected, required this.onSelect, this.padding = const EdgeInsets.symmetric(horizontal: 20)});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24 + MediaQuery.textScalerOf(context).scale(20),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => BrandChip(label: labels[i], selected: i == selected, onTap: () => onSelect(i)),
        ),
      );
}

/// Segmented control ("Tuần / Tháng / Năm", "Cảm nhận / Thảo luận").
class Segmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const Segmented({super.key, required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == selected,
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i == selected) return;
                    HapticFeedback.selectionClick();
                    onSelect(i);
                  },
                  // Min height, not fixed: labels must not clip at large text.
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? AppColors.bg : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: i == selected ? [BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.08 : 0.3), blurRadius: 4, offset: const Offset(0, 1))] : null,
                    ),
                    child: Text(labels[i], textAlign: TextAlign.center, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: i == selected ? AppColors.text : AppColors.textSecondary))),
                  ),
                ),
                ),
              ),
          ],
        ),
      );
}

/// Underlined tab row ("Lời bài hát · Bản nhạc · Bình luận").
class UnderlineTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const UnderlineTabs({super.key, required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        height: 50,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 22),
          itemBuilder: (_, i) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(i);
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == selected ? AppColors.wine : Colors.transparent, width: 3))),
              child: Text(labels[i], style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: i == selected ? AppColors.text : AppColors.textMuted))),
            ),
          ),
        ),
      );
}

/// Primary (wine) / secondary (soft) pill button, 50px tall.
class PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool loading;
  final double height;
  const PillButton({super.key, required this.label, this.icon, this.onTap, this.primary = true, this.loading = false, this.height = 50});

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.wine : AppColors.surface;
    final fg = primary ? Colors.white : AppColors.text;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(height / 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(height / 2),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
                else if (icon != null)
                  Icon(icon, size: 22, color: fg),
                if (icon != null || loading) const SizedBox(width: 8),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg)))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled round action ("Yêu thích · 60", "Tải về", "Lưu", "Chia sẻ").
class LabeledAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  const LabeledAction({super.key, required this.icon, required this.label, this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: active ? AppColors.accentSoft : AppColors.surface, shape: BoxShape.circle),
                  child: Icon(icon, size: 22, color: active ? AppColors.accentLight : AppColors.text),
                ),
                const SizedBox(height: 6),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
              ],
            ),
          ),
        ),
      );
}

/// Pulsing grey block for loading states.
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final EdgeInsets margin;
  const Skeleton({super.key, this.width, required this.height, this.radius = 10, this.margin = EdgeInsets.zero});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.55).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

/// Skeleton matching a SongRow.
class SkeletonSongRow extends StatelessWidget {
  const SkeletonSongRow({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          Skeleton(width: 52, height: 52, radius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FractionallySizedBox(widthFactor: 0.7, child: Skeleton(height: 14)),
              SizedBox(height: 8),
              FractionallySizedBox(widthFactor: 0.45, child: Skeleton(height: 11)),
            ]),
          ),
        ]),
      );
}

/// Friendly empty / error block with an optional action.
class EmptyBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;
  const EmptyBlock({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(36, 40, 36, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: AppColors.accentLight),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
            ],
            if (action != null && onAction != null) ...[
              const SizedBox(height: 20),
              PillButton(label: action!, onTap: onAction),
            ],
          ],
        ),
      );
}

/// The one "no network" message every screen shows when a fetch fails,
/// so an empty list is never mistaken for "there are no songs".
class OfflineBlock extends StatelessWidget {
  final VoidCallback onRetry;
  const OfflineBlock({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) => EmptyBlock(
        icon: Icons.wifi_off_rounded,
        title: 'Chưa tải được nội dung',
        message: 'Kiểm tra kết nối mạng rồi thử lại. Các bài đã tải về vẫn nghe được.',
        action: 'Tải lại',
        onAction: onRetry,
      );
}

/// Back arrow behaviour for every screen: pop when there is somewhere to go
/// back to, otherwise (opened from a notification or shared link) go home
/// instead of doing nothing or closing the app.
/// Root of the tab the user is in (set by the shell), for [goBack].
String Function() goBackFallback = () => '/';

void goBack(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
  } else {
    GoRouter.of(context).go(goBackFallback());
  }
}

/// Lets a horizontal strip inside a 20px-padded column run to both screen
/// edges (content still starts on the 20px line), like the other rails.
class BleedRow extends StatelessWidget {
  final Widget Function(EdgeInsets padding) builder;
  final double inset;
  final double height;
  const BleedRow({super.key, required this.builder, required this.height, this.inset = 20});

  @override
  // A fixed height: an OverflowBox inside a Column would otherwise take
  // infinite height and blank out the rest of the page.
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: LayoutBuilder(
        builder: (_, c) => OverflowBox(
          // Wider than the parent on purpose; OverflowBox keeps it centred,
          // so it reaches both screen edges.
          minWidth: c.maxWidth + inset * 2,
          maxWidth: c.maxWidth + inset * 2,
          child: builder(EdgeInsets.symmetric(horizontal: inset)),
        ),
      ),
      );
}

/// Glue the last two words of a short headline with a no-break space so a
/// wrapped title never leaves one word alone on its line
/// ("Đất nước anh hùng / ca" → "Đất nước anh / hùng ca").
String noOrphan(String s) {
  final t = s.trim();
  final i = t.lastIndexOf(' ');
  if (i <= 0 || t.length - i > 14 || t.split(' ').length < 3) return t;
  return '${t.substring(0, i)}\u00A0${t.substring(i + 1)}';
}

/// Square-ish media card used in horizontal rails (cover + 2-line title +
/// subtitle). [cover] is the artwork widget.
class RailCard extends StatelessWidget {
  final Widget cover;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final double width;
  final double coverHeight;
  /// Small grey line under the subtitle ("Hôm qua").
  final String? meta;
  const RailCard({super.key, required this.cover, required this.title, this.subtitle, this.onTap, this.width = 148, double? coverHeight, this.meta}) : coverHeight = coverHeight ?? width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        // One VoiceOver stop per card ("Tên bài, ca sĩ, nút") instead of loose text.
        child: Semantics(
          button: onTap != null,
          label: [title, if (subtitle != null && subtitle!.isNotEmpty) subtitle, if (meta != null && meta!.isNotEmpty) meta].join(', '),
          excludeSemantics: true,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(18), child: SizedBox(width: width, height: coverHeight, child: cover)),
              const SizedBox(height: 10),
              Text(noOrphan(title), maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.text))),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ),
              if (meta != null && meta!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted))),
                ),
            ],
          ),
        ),
        ),
      );
}

/// Horizontal rail wrapper with the standard 20px inset and 12px gap.
class Rail extends StatelessWidget {
  final double height;
  final int count;
  final IndexedWidgetBuilder builder;
  final double gap;
  /// Part of [height] taken by text under the card; it grows with the
  /// "Cỡ chữ" setting so captions never clip at Lớn / Rất lớn.
  final double textHeight;
  const Rail({super.key, required this.height, required this.count, required this.builder, this.gap = 12, this.textHeight = 60});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height - textHeight + MediaQuery.textScalerOf(context).scale(textHeight),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: count,
          separatorBuilder: (_, __) => SizedBox(width: gap),
          itemBuilder: builder,
        ),
      );
}

/// Round person avatar + name, for Nhạc sĩ / Nghệ sĩ strips.
class PersonBubble extends StatelessWidget {
  final String name;
  final String? image;
  final VoidCallback? onTap;
  final double size;
  final bool tint;
  const PersonBubble({super.key, required this.name, this.image, this.onTap, this.size = 88, this.tint = true});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Semantics(
      button: onTap != null,
      label: name,
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
      width: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            NetImage(
              url: image,
              width: size,
              height: size,
              circle: true,
              tint: tint,
              fallback: Container(
                width: size,
                height: size,
                color: AppColors.accentSoft,
                alignment: Alignment.center,
                child: Text(initial, style: display(TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
              ),
            ),
            const SizedBox(height: 8),
            Text(name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.text))),
          ],
        ),
      ),
    ),
    );
  }
}

/// Letter avatar / photo avatar for users.
class UserAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  const UserAvatar({super.key, this.url, required this.name, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return NetImage(
      url: url,
      width: size,
      height: size,
      circle: true,
      fallback: Container(
        width: size,
        height: size,
        color: AppColors.accentSoft,
        alignment: Alignment.center,
        child: Text(initial, style: body(TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
      ),
    );
  }
}

/// Simple settings/list item row with leading icon tile and chevron.
class ListItem extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  const ListItem({super.key, this.icon, required this.title, this.subtitle, this.trailingText, this.trailing, this.onTap, this.titleColor});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, size: 21, color: AppColors.text),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: titleColor ?? AppColors.text))),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                        ),
                    ],
                  ),
                ),
                if (trailingText != null) Text(trailingText!, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                if (trailing != null) trailing! else if (onTap != null) Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      );
}

/// "HOẠT ĐỘNG CỦA TÔI" style group label.
class GroupLabel extends StatelessWidget {
  final String text;
  const GroupLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(text.toUpperCase(), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted))),
      );
}

/// Sub-page top bar: back, centered title, optional actions.
class SubPageBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  const SubPageBar({super.key, this.title = '', this.actions = const []});
  @override
  Size get preferredSize => const Size.fromHeight(52);
  @override
  Widget build(BuildContext context) => AppBar(
        toolbarHeight: 52,
        backgroundColor: AppColors.bg,
        // Opened from a notification or link there is nothing to pop to;
        // keep the arrow and take the user home instead of stranding them.
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).canPop() ? Navigator.of(context).maybePop() : GoRouter.of(context).go('/'),
        ),
        title: Text(title),
        actions: [...actions, const SizedBox(width: 6)],
      );
}


// ---------------------------------------------------------------------------
// Song-list sorting + page-based paging, shared by every list screen so the
// sort row, the pager and the loading/offline states look and behave the
// same everywhere (2026-11 consistency pass).
// ---------------------------------------------------------------------------

/// The four standard sort tabs for song lists, in display order. A screen
/// shows only the ones its query can order by (see [kSongSortColumn]).
const kSongSorts = <String>['Nghe nhiều nhất', 'Mới cập nhật', 'Yêu thích nhất', 'Tải nhiều nhất'];

/// `orderBy` column for each label in [kSongSorts]. "Mới cập nhật" orders
/// by id (newest upload first), same as the web.
const kSongSortColumn = <String, String>{
  'Nghe nhiều nhất': 'views',
  'Mới cập nhật': 'id',
  'Yêu thích nhất': 'likes',
  'Tải nhiều nhất': 'downloads',
};

/// [SongRow.metricKey] matching each sort, so the row shows the number
/// the list is sorted by ("1,2 N lượt nghe", "3 ngày trước", ...).
const kSongSortMetric = <String, String>{
  'Nghe nhiều nhất': 'views',
  'Mới cập nhật': 'time',
  'Yêu thích nhất': 'likes',
  'Tải nhiều nhất': 'downloads',
};

/// Sort row ("Nghe nhiều nhất · Mới cập nhật · ..."): [BrandChip] pills,
/// 44pt tall, horizontally scrollable. Tapping the active tab does nothing.
class SortTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final EdgeInsets padding;
  const SortTabs({super.key, required this.labels, required this.selected, required this.onSelect, this.padding = const EdgeInsets.symmetric(horizontal: 20)});

  @override
  Widget build(BuildContext context) {
    if (labels.length < 2) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Sắp xếp',
      explicitChildNodes: true,
      child: ChipStrip(
        labels: labels,
        selected: selected.clamp(0, labels.length - 1),
        padding: padding,
        onSelect: (i) {
          if (i != selected) onSelect(i);
        },
      ),
    );
  }
}

/// Big pager for older users: "‹ Trước" / "Sau ›" buttons (48pt), the
/// current position "Trang X / Y" in words, and numbered pages above when
/// the screen is wide enough. Hidden when there is only one page.
class Pager extends StatelessWidget {
  final int page;
  final int lastPage;
  final ValueChanged<int> onPage;
  /// Disables every button while a page is on its way.
  final bool loading;
  const Pager({super.key, required this.page, required this.lastPage, required this.onPage, this.loading = false});

  @override
  Widget build(BuildContext context) {
    if (lastPage <= 1) return const SizedBox.shrink();
    final cur = page.clamp(1, lastPage);
    return LayoutBuilder(builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      // Five 48pt numbers + gaps need ~300pt; skip them on narrow or
      // large-text screens rather than wrap into a messy second row.
      final showNumbers = c.maxWidth >= 300 * scale.clamp(1.0, 2.0);
      final nums = <Widget>[];
      if (showNumbers) {
        final pages = <int>{1, lastPage, for (var i = -1; i <= 1; i++) if (cur + i >= 1 && cur + i <= lastPage) cur + i}.toList()..sort();
        var prev = 0;
        for (final p in pages) {
          if (prev != 0 && p - prev > 1) {
            nums.add(ExcludeSemantics(child: Text('…', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))));
          }
          nums.add(_PagerNumber(page: p, active: p == cur, enabled: !loading && p != cur, onTap: () => onPage(p)));
          prev = p;
        }
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nums.isNotEmpty) ...[
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: nums),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              _PagerStep(label: '‹ Trước', semantic: 'Trang trước', enabled: !loading && cur > 1, onTap: () => onPage(cur - 1)),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: 'Trang $cur trên $lastPage',
                  excludeSemantics: true,
                  child: Text('Trang $cur / $lastPage', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                ),
              ),
              _PagerStep(label: 'Sau ›', semantic: 'Trang sau', enabled: !loading && cur < lastPage, onTap: () => onPage(cur + 1)),
            ],
          ),
        ],
      );
    });
  }
}

class _PagerStep extends StatelessWidget {
  final String label;
  final String semantic;
  final bool enabled;
  final VoidCallback onTap;
  const _PagerStep({required this.label, required this.semantic, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: enabled,
        label: semantic,
        excludeSemantics: true,
        child: Material(
          color: enabled ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap();
                  }
                : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
              child: Text(label, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: enabled ? AppColors.text : AppColors.textMuted))),
            ),
          ),
        ),
      );
}

class _PagerNumber extends StatelessWidget {
  final int page;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _PagerNumber({required this.page, required this.active, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = active ? (AppColors.isLight ? AppColors.wine : AppColors.accent) : AppColors.surface;
    final fg = active ? Colors.white : (enabled ? AppColors.text : AppColors.textMuted);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: active,
      label: active ? 'Trang $page, đang xem' : 'Trang $page',
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            child: Text('$page', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg))),
          ),
        ),
      ),
    );
  }
}

/// One page of a Lighthouse paginator.
class PageResult<T> {
  final List<T> items;
  final int page;
  final int lastPage;
  final int total;
  const PageResult({required this.items, required this.page, required this.lastPage, required this.total});

  /// Reads `{ data [...] paginatorInfo { currentPage lastPage total } }`;
  /// [map] adapts each row (e.g. sets `file_type`).
  static PageResult<Map<String, dynamic>> fromPaginator(dynamic raw, int page, [Map<String, dynamic> Function(Map<String, dynamic>)? map]) {
    final pi = (raw is Map ? raw['paginatorInfo'] : null) ?? const {};
    final rows = ((raw is Map ? raw['data'] : null) ?? const []) as List;
    final items = <Map<String, dynamic>>[];
    for (final e in rows) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      items.add(map == null ? m : map(m));
    }
    return PageResult(
      items: items,
      page: (pi['currentPage'] as num?)?.toInt() ?? page,
      lastPage: (pi['lastPage'] as num?)?.toInt() ?? 1,
      total: (pi['total'] as num?)?.toInt() ?? items.length,
    );
  }
}

/// State of one page-based list: the page on screen plus loading/failed
/// flags. [sort] is an index into the screen's own sort labels.
class PagedList<T> {
  PagedList({this.sort = 0});
  List<T> items = [];
  int page = 1;
  int lastPage = 1;
  int total = 0;
  int sort;
  bool loading = false;
  bool failed = false;
  /// A page has arrived at least once (header shows the total, not "Đang tải...").
  bool loaded = false;
  int _req = 0;

  /// Back to an empty first page; any request still in flight is dropped.
  void reset({int sort = 0}) {
    items = [];
    page = 1;
    lastPage = 1;
    total = 0;
    this.sort = sort;
    loading = false;
    failed = false;
    loaded = false;
    _req++;
  }
}

/// Loads pages into [PagedList]s for a [State]. Older responses that land
/// late are dropped (request token). On failure the page already on screen
/// stays (with a "Thử lại" snackbar); with nothing to show, [PagedList.failed]
/// makes the body show [OfflineBlock].
mixin PagedLoader<W extends StatefulWidget> on State<W> {
  Future<void> loadPage<T>(
    PagedList<T> list,
    int page,
    Future<PageResult<T>> Function(int page, int sort) fetch, {
    int? sort,
    ScrollController? scrollToTop,
    VoidCallback? onLoaded,
  }) async {
    final useSort = sort ?? list.sort;
    final prevSort = list.sort;
    final req = ++list._req;
    setState(() {
      list.sort = useSort;
      list.loading = true;
      list.failed = false;
    });
    try {
      final r = await fetch(page, useSort);
      if (req != list._req || !mounted) return;
      setState(() {
        list.items = r.items;
        list.page = r.page;
        list.lastPage = r.lastPage < 1 ? 1 : r.lastPage;
        list.total = r.total;
        list.loading = false;
        list.loaded = true;
      });
      // New page / sort: read from the top, not from where the pager was.
      final c = scrollToTop;
      if (c != null && c.hasClients && c.offset > 0) {
        c.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
      onLoaded?.call();
    } catch (e) {
      if (req != list._req || !mounted) return;
      final kept = list.items.isNotEmpty;
      setState(() {
        list.loading = false;
        if (kept) {
          list.sort = prevSort; // tab must match the list still shown
        } else {
          list.failed = true;
        }
      });
      if (kept) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          action: SnackBarAction(label: 'Thử lại', onPressed: () => loadPage(list, page, fetch, sort: useSort, scrollToTop: scrollToTop, onLoaded: onLoaded)),
        ));
      }
    }
  }
}

/// Body of a page-based list, as a widget list for a Column / SliverList:
/// skeleton while a page loads, [OfflineBlock] when nothing could be
/// loaded, an empty note, or the rows followed by the [Pager].
List<Widget> pagedListBody<T>(
  PagedList<T> list, {
  required Widget Function(T item, int index) itemBuilder,
  required VoidCallback onRetry,
  required ValueChanged<int> onPage,
  int perPage = 10,
  String emptyText = 'Chưa có bài',
  Widget? skeleton,
  Widget? empty,
}) {
  if (list.loading || (!list.loaded && !list.failed)) {
    return [skeleton ?? const SongListSkeleton(rows: 8, showIndex: true)];
  }
  if (list.failed && list.items.isEmpty) return [OfflineBlock(onRetry: onRetry)];
  if (list.items.isEmpty) {
    return [
      empty ??
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(emptyText, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))),
          ),
    ];
  }
  final base = (list.page - 1) * perPage;
  return [
    for (var i = 0; i < list.items.length; i++) itemBuilder(list.items[i], base + i),
    if (list.lastPage > 1)
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Pager(page: list.page, lastPage: list.lastPage, loading: list.loading, onPage: onPage),
      ),
  ];
}
