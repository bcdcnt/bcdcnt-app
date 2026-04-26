import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Animated diagonal sheen sweeping across child to fake skeleton loading.
class Shimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;
  const Shimmer({
    super.key,
    required this.child,
    this.baseColor = AppColors.surfaceLight,
    this.highlightColor = const Color(0xFF302424),
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (ctx, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * 2 * _ctl.value - bounds.width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [widget.baseColor, widget.highlightColor, widget.baseColor],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideTransform(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideTransform extends GradientTransform {
  final double dx;
  const _SlideTransform(this.dx);
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// Quick rectangle placeholder.
class SkBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkBox({super.key, this.width, this.height = 14, this.radius = 8});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(radius)),
  );
}
