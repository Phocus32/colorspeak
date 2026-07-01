import 'package:flutter/material.dart';

class ColorMatch {
  final String name;
  final int r;
  final int g;
  final int b;
  final Color displayColor;

  const ColorMatch({
    required this.name,
    required this.r,
    required this.g,
    required this.b,
    required this.displayColor,
  });

  double distanceTo(int pr, int pg, int pb) {
    final dr = (r - pr).toDouble();
    final dg = (g - pg).toDouble();
    final db = (b - pb).toDouble();
    return (dr * dr * 0.299) + (dg * dg * 0.587) + (db * db * 0.114);
  }
}

class ColorDatabase {
  static const List<ColorMatch> colors = [
    ColorMatch(name: 'Red',     r: 220, g: 20,  b: 30,  displayColor: Color(0xFFDC141E)),
    ColorMatch(name: 'Orange',  r: 255, g: 140, b: 0,   displayColor: Color(0xFFFF8C00)),
    ColorMatch(name: 'Yellow',  r: 255, g: 220, b: 0,   displayColor: Color(0xFFFFDC00)),
    ColorMatch(name: 'Lime',    r: 50,  g: 205, b: 50,  displayColor: Color(0xFF32CD32)),
    ColorMatch(name: 'Green',   r: 0,   g: 140, b: 60,  displayColor: Color(0xFF008C3C)),
    ColorMatch(name: 'Teal',    r: 0,   g: 128, b: 128, displayColor: Color(0xFF008080)),
    ColorMatch(name: 'Cyan',    r: 0,   g: 210, b: 230, displayColor: Color(0xFF00D2E6)),
    ColorMatch(name: 'Blue',    r: 30,  g: 100, b: 220, displayColor: Color(0xFF1E64DC)),
    ColorMatch(name: 'Navy',    r: 0,   g: 0,   b: 128, displayColor: Color(0xFF000080)),
    ColorMatch(name: 'Purple',  r: 128, g: 0,   b: 128, displayColor: Color(0xFF800080)),
    ColorMatch(name: 'Magenta', r: 220, g: 0,   b: 220, displayColor: Color(0xFFDC00DC)),
    ColorMatch(name: 'Pink',    r: 255, g: 150, b: 170, displayColor: Color(0xFFFF96AA)),
    ColorMatch(name: 'Brown',   r: 139, g: 69,  b: 19,  displayColor: Color(0xFF8B4513)),
    ColorMatch(name: 'Maroon',  r: 128, g: 0,   b: 0,   displayColor: Color(0xFF800000)),
    ColorMatch(name: 'Olive',   r: 128, g: 128, b: 0,   displayColor: Color(0xFF808000)),
    ColorMatch(name: 'White',   r: 245, g: 245, b: 245, displayColor: Color(0xFFF5F5F5)),
    ColorMatch(name: 'Gray',    r: 128, g: 128, b: 128, displayColor: Color(0xFF808080)),
    ColorMatch(name: 'Black',   r: 20,  g: 20,  b: 20,  displayColor: Color(0xFF141414)),
  ];

  static ColorMatch findNearest(int r, int g, int b) {
    ColorMatch best = colors.first;
    double bestDist = double.maxFinite;

    for (final c in colors) {
      final d = c.distanceTo(r, g, b);
      if (d < bestDist) {
        bestDist = d;
        best = c;
      }
    }
    return best;
  }

  static Color contrastTextColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.35 ? Colors.black : Colors.white;
  }
}
