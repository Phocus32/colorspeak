import 'package:flutter/material.dart';

class ScanOverlay extends StatefulWidget {
  final Color ringColor;
  final bool isScanning;

  const ScanOverlay({
    super.key,
    required this.ringColor,
    required this.isScanning,
  });

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        return CustomPaint(
          painter: _ScanBoxPainter(
            ringColor: widget.ringColor,
            glowOpacity: widget.isScanning ? _pulseAnim.value : 0.3,
          ),
        );
      },
    );
  }
}

class _ScanBoxPainter extends CustomPainter {
  final Color ringColor;
  final double glowOpacity;

  _ScanBoxPainter({required this.ringColor, required this.glowOpacity});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const boxSize = 130.0;
    const half = boxSize / 2;
    const cornerLen = 22.0;
    const cornerRadius = 6.0;

    final boxRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: boxSize,
      height: boxSize,
    );

    final outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final innerPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
          boxRect, const Radius.circular(cornerRadius)));
    final dimmingPath =
        Path.combine(PathOperation.difference, outerPath, innerPath);

    canvas.drawPath(
      dimmingPath,
      Paint()..color = Colors.black.withOpacity(0.55),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          boxRect.inflate(6), const Radius.circular(cornerRadius + 6)),
      Paint()
        ..color = ringColor.withOpacity(glowOpacity * 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(cornerRadius)),
      Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    final cornerPaint = Paint()
      ..color = ringColor.withOpacity(0.85 + glowOpacity * 0.15)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final corners = [
      [
        Offset(cx - half, cy - half + cornerLen),
        Offset(cx - half, cy - half),
        Offset(cx - half + cornerLen, cy - half)
      ],
      [
        Offset(cx + half - cornerLen, cy - half),
        Offset(cx + half, cy - half),
        Offset(cx + half, cy - half + cornerLen)
      ],
      [
        Offset(cx + half, cy + half - cornerLen),
        Offset(cx + half, cy + half),
        Offset(cx + half - cornerLen, cy + half)
      ],
      [
        Offset(cx - half + cornerLen, cy + half),
        Offset(cx - half, cy + half),
        Offset(cx - half, cy + half - cornerLen)
      ],
    ];

    for (final pts in corners) {
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy);
      canvas.drawPath(path, cornerPaint);
    }

    canvas.drawCircle(
      Offset(cx, cy),
      3.0,
      Paint()..color = ringColor.withOpacity(0.8 * glowOpacity),
    );
  }

  @override
  bool shouldRepaint(_ScanBoxPainter old) =>
      old.ringColor != ringColor || old.glowOpacity != glowOpacity;
}
