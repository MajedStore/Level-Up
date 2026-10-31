import 'package:flutter/material.dart';

/// The standard multicolour Google "G", drawn from Google's published
/// 48×48 sign-in button artwork so it stays sharp at any density.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Google',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _GoogleLogoPainter()),
    ),
  );
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const _paths = [
    (
      Color(0xFFEA4335),
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
          '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
    ),
    (
      Color(0xFF4285F4),
      'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
          '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
    ),
    (
      Color(0xFFFBBC05),
      'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
          'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
    ),
    (
      Color(0xFF34A853),
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
          '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z',
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    for (final (color, data) in _paths) {
      canvas.drawPath(_parse(data), Paint()..color = color);
    }
  }

  /// Minimal SVG path parser covering the commands used above.
  static Path _parse(String data) {
    final tokens = RegExp(
      r'[MmCcSsLlHhVvZz]|-?(?:\d+\.?\d*|\.\d+)',
    ).allMatches(data).map((m) => m.group(0)!).toList();
    final path = Path();
    var i = 0;
    var command = '';
    var x = 0.0, y = 0.0;
    var cx = 0.0, cy = 0.0;
    double next() => double.parse(tokens[i++]);
    while (i < tokens.length) {
      if (RegExp('[A-Za-z]').hasMatch(tokens[i])) command = tokens[i++];
      final relative = command == command.toLowerCase();
      final ox = relative ? x : 0.0, oy = relative ? y : 0.0;
      switch (command.toUpperCase()) {
        case 'M':
          x = ox + next();
          y = oy + next();
          path.moveTo(x, y);
          command = relative ? 'l' : 'L';
        case 'L':
          x = ox + next();
          y = oy + next();
          path.lineTo(x, y);
        case 'H':
          x = (relative ? x : 0) + next();
          path.lineTo(x, y);
        case 'V':
          y = (relative ? y : 0) + next();
          path.lineTo(x, y);
        case 'C':
          final x1 = ox + next(), y1 = oy + next();
          cx = ox + next();
          cy = oy + next();
          x = ox + next();
          y = oy + next();
          path.cubicTo(x1, y1, cx, cy, x, y);
        case 'S':
          final x1 = 2 * x - cx, y1 = 2 * y - cy;
          cx = ox + next();
          cy = oy + next();
          x = ox + next();
          y = oy + next();
          path.cubicTo(x1, y1, cx, cy, x, y);
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
