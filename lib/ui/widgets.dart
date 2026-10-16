import 'package:flutter/material.dart';

import '../db/models.dart';
import '../theme.dart';

/// 1px top inner highlight — the mockup's `inset 0 1px 0` light-catch
/// that makes surfaces read as layered instead of flat.
class _TopHighlight extends StatelessWidget {
  const _TopHighlight({this.alpha = 0.9, this.inset = 14});
  final double alpha;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: inset,
      right: inset,
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

/// Bottom inner shadow — the mockup's `inset 0 -2px 4px rgba(0,0,0,.1)`,
/// grounding gradient buttons and the hero.
class _BottomInnerShadow extends StatelessWidget {
  const _BottomInnerShadow({this.alpha = 0.1, this.height = 8});
  final double alpha;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(14),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: alpha),
            ],
          ),
        ),
      ),
    );
  }
}

/// Layered card with soft deep shadows + top highlight (mockup v3).
/// [soft] = the lighter row variant (dose rows, med cards, settings rows).
class DepthCard extends StatelessWidget {
  const DepthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.soft = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final tappable = onTap != null || onLongPress != null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFFDFCF9)],
        ),
        border: Border.all(color: DoseWiseColors.cardBorder),
        boxShadow: soft
            ? const [
                // .trow/.medcard/.setrow: 0 8px 22px rgba(34,49,45,.10)
                BoxShadow(
                  color: Color(0x1A22312D),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ]
            : const [
                // .card: 0 16px 36px rgba(34,49,45,.14),
                //        0 3px 8px rgba(34,49,45,.08)
                BoxShadow(
                  color: Color(0x2422312D),
                  blurRadius: 36,
                  offset: Offset(0, 16),
                ),
                BoxShadow(
                  color: Color(0x1422312D),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            const _TopHighlight(),
            Material(
              color: Colors.transparent,
              child: tappable
                  ? InkWell(
                      onTap: onTap,
                      onLongPress: onLongPress,
                      borderRadius: radius,
                      child: Padding(padding: padding, child: child),
                    )
                  : Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// Primary button with the mockup's teal gradient + glow (v3).
/// Replaces FilledButton for primary CTAs (Taken, Save, Get started…).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.expanded = true,
  });
  final VoidCallback? onPressed;
  final Widget child;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(14);
    final button = Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: enabled
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF16AD87), Color(0xFF0A6357)],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFB9C2C0), Color(0xFF9AA3A0)],
              ),
        boxShadow: enabled
            ? const [
                // .bigbtn: 0 14px 30px rgba(14,124,107,.45)
                BoxShadow(
                  color: Color(0x730E7C6B),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            if (enabled) ...[
              const _TopHighlight(alpha: 0.32, inset: 12),
              const _BottomInnerShadow(alpha: 0.12, height: 10),
            ],
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: radius,
                child: Center(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// DoseWise logo (mockup v3, LOCKED): teal-gradient rounded tile +
/// white two-tone capsule tilted -28° with center seam + white badge
/// with teal check at bottom-right. Faithful to the SVG reference
/// (gradient ids dwlg/dwlg2 in mockup-v1.html).
class DoseWiseLogo extends StatelessWidget {
  const DoseWiseLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DoseWiseLogoPainter(),
    );
  }
}

class _DoseWiseLogoPainter extends CustomPainter {
  static const double _r = 3.141592653589793 / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.save();
    canvas.scale(s);

    // Drop shadow: 0 12px 24px rgba(14,124,107,.4).
    canvas.save();
    canvas.translate(0, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 3, 58, 58),
        const Radius.circular(17),
      ),
      Paint()
        ..color = const Color(0x660E7C6B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.restore();

    // Tile: diagonal gradient #16AD87 → #09584E.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 3, 58, 58),
        const Radius.circular(17),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16AD87), Color(0xFF09584E)],
        ).createShader(const Rect.fromLTWH(0, 0, 64, 64)),
    );
    // Inner edge light: 1px white at 28% opacity.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.5, 3.5, 57, 57),
        const Radius.circular(16.5),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.28),
    );

    // Capsule, tilted -28° about (32, 30).
    canvas.save();
    canvas.translate(32, 30);
    canvas.rotate(-28 * _r);
    canvas.translate(-32, -30);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(17, 24, 30, 13),
        const Radius.circular(6.5),
      ),
      Paint()..color = Colors.white,
    );
    // Two-tone left half (#CDE9DF).
    final tone = Path()
      ..moveTo(17, 30.5)
      ..arcToPoint(const Offset(23.5, 24),
          radius: const Radius.circular(6.5))
      ..lineTo(32, 24)
      ..lineTo(32, 37)
      ..lineTo(23.5, 37)
      ..arcToPoint(const Offset(17, 30.5),
          radius: const Radius.circular(6.5))
      ..close();
    canvas.drawPath(tone, Paint()..color = const Color(0xFFCDE9DF));
    // Center seam.
    canvas.drawLine(
      const Offset(32, 24.5),
      const Offset(32, 36.5),
      Paint()
        ..color = const Color(0xFF0A5C51)
        ..strokeWidth = 2,
    );
    canvas.restore();

    // Badge: white circle + teal check.
    canvas.drawCircle(
        const Offset(47, 46), 10.5, Paint()..color = Colors.white);
    final check = Path()
      ..moveTo(42.3, 46.2)
      ..lineTo(45.6, 49.5)
      ..lineTo(51.5, 43.2);
    canvas.drawPath(
      check,
      Paint()
        ..color = const Color(0xFF0A5C51)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small colored status pill for a dose row.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});
  final DoseStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (status) {
      case DoseStatus.taken:
        bg = DoseWiseColors.tealSoft;
        fg = DoseWiseColors.tealDark;
        label = 'Taken ✓';
        break;
      case DoseStatus.pending:
        bg = DoseWiseColors.amberSoft;
        fg = DoseWiseColors.amberDark;
        label = 'Pending';
        break;
      case DoseStatus.snoozed:
        bg = DoseWiseColors.amberSoft;
        fg = DoseWiseColors.amberDark;
        label = 'Snoozed';
        break;
      case DoseStatus.skipped:
        bg = const Color(0xFFECEFF0);
        fg = DoseWiseColors.muted;
        label = 'Skipped';
        break;
      case DoseStatus.missed:
        bg = DoseWiseColors.redSoft;
        fg = DoseWiseColors.red;
        label = 'Missed';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Small-caps section label used across screens.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: DoseWiseColors.faint,
        ),
      ),
    );
  }
}

/// Circular pill/capsule glyph (no emoji — inline SVG-style custom paint).
class PillGlyph extends StatelessWidget {
  const PillGlyph(
      {super.key, this.size = 40, this.color = DoseWiseColors.teal});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PillPainter(color),
    );
  }
}

class _PillPainter extends CustomPainter {
  _PillPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = size.width / 2;
    canvas.drawCircle(Offset(r, r), r, paint);
    final half = Paint()..color = Colors.white.withValues(alpha: 0.35);
    canvas.save();
    canvas.translate(r, r);
    canvas.rotate(-0.6);
    canvas.drawRect(Rect.fromLTWH(-r, -r, r, 2 * r), half);
    canvas.restore();
    // split line
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = size.width * 0.07;
    canvas.save();
    canvas.translate(r, r);
    canvas.rotate(-0.6);
    canvas.drawLine(const Offset(0, 0), Offset(0, 0), line);
    canvas.drawLine(Offset(-r * 0.95, 0), Offset(r * 0.95, 0), line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Flame glyph for the streak.
class FlameGlyph extends StatelessWidget {
  const FlameGlyph({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.2),
      painter: _FlamePainter(),
    );
  }
}

class _FlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = DoseWiseColors.amber;
    final path = Path()
      ..moveTo(size.width * 0.5, 0)
      ..cubicTo(size.width * 0.7, size.height * 0.35, size.width * 0.95,
          size.height * 0.55, size.width * 0.95, size.height * 0.75)
      ..cubicTo(size.width * 0.95, size.height * 0.95, size.width * 0.72,
          size.height, size.width * 0.5, size.height)
      ..cubicTo(size.width * 0.28, size.height, size.width * 0.05,
          size.height * 0.95, size.width * 0.05, size.height * 0.75)
      ..cubicTo(size.width * 0.05, size.height * 0.5, size.width * 0.35,
          size.height * 0.4, size.width * 0.5, 0)
      ..close();
    canvas.drawPath(path, paint);
    final inner = Paint()..color = const Color(0xFFFFD98A);
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.72),
        size.width * 0.18,
        inner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Streak flame chip in the Today header (taps through to Stats).
/// Mockup v3: soft amber glow + top highlight.
class StreakChip extends StatelessWidget {
  const StreakChip(
      {super.key, required this.streak, required this.onTap});
  final int streak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: DoseWiseColors.amberSoft,
          borderRadius: BorderRadius.circular(20),
          // .streak: 0 6px 14px rgba(232,147,12,.3)
          boxShadow: const [
            BoxShadow(
              color: Color(0x4DE8930C),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              const _TopHighlight(alpha: 0.55, inset: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FlameGlyph(size: 14),
                  const SizedBox(width: 4),
                  Text('$streak',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: DoseWiseColors.amberDark)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty-state block: logo + message + CTA.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    required this.ctaLabel,
    required this.onCta,
  });
  final String message;
  final String ctaLabel;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DoseWiseLogo(size: 64),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, color: DoseWiseColors.muted)),
            const SizedBox(height: 16),
            GradientButton(onPressed: onCta, child: Text(ctaLabel)),
          ],
        ),
      ),
    );
  }
}
