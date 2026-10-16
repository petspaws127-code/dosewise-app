import 'package:flutter/material.dart';

import '../db/models.dart';
import '../theme.dart';

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

/// Streak flame chip used in the Today header (taps through to Stats).
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: DoseWiseColors.amberSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
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
      ),
    );
  }
}

/// Empty-state block: glyph + message + CTA.
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
            const PillGlyph(size: 56, color: DoseWiseColors.tealSofter),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, color: DoseWiseColors.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onCta, child: Text(ctaLabel)),
          ],
        ),
      ),
    );
  }
}
