import 'package:flutter/material.dart';

/// Mirror of bcdcnt-web's two-column page layout: main flex-1 column on the
/// left, fixed-width side column on the right. Below the desktop breakpoint
/// the side content is dropped entirely (mobile pages already handle their
/// own related sections inline, so we don't double-render).
class DesktopColumns extends StatelessWidget {
  final Widget main;
  final Widget side;
  final double sideWidth;
  final double gap;
  final double breakpoint;

  const DesktopColumns({
    super.key,
    required this.main,
    required this.side,
    this.sideWidth = 340,
    this.gap = 32,
    this.breakpoint = 900,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < breakpoint) return main;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        SizedBox(width: gap),
        SizedBox(width: sideWidth, child: side),
      ],
    );
  }
}
