import 'package:flutter/material.dart';

/// Design tokens for NetGet's «خيوط» (Threads) visual identity.
/// Rooted in Sudanese desert, clay, and river aesthetics.
class ThreadTokens {
  // Sudanese Desert & River Palette
  static const Color desertAmber = Color(0xFFE09F3E);
  static const Color warmSand = Color(0xFFF3D2A2);
  static const Color nileBlue = Color(0xFF0F4C5C);
  static const Color deepRiver = Color(0xFF1B3B6F);
  static const Color clayTerracotta = Color(0xFFC85A32);
  static const Color earthRed = Color(0xFF9E2A2B);
  static const Color acaciaGreen = Color(0xFF2E7D32);
  static const Color paperWhite = Color(0xFFFAFAF9);
  static const Color darkSlate = Color(0xFF121820);
  static const Color cardDark = Color(0xFF1A222D);

  // Distinct colors for concurrent download thread strands (خيوط التحميل)
  static const List<Color> threadStrands = [
    Color(0xFFE09F3E), // Amber
    Color(0xFF0F4C5C), // Nile
    Color(0xFF26A69A), // Teal
    Color(0xFFC85A32), // Terracotta
    Color(0xFF5E60CE), // Indigo
    Color(0xFF48CAE4), // River Sky
    Color(0xFFF77F00), // Ochre
    Color(0xFF06D6A0), // Emerald
  ];

  static Color threadColor(int index) {
    return threadStrands[index % threadStrands.length];
  }

  // Radii
  static const double radiusXs = 4.0;
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 14.0;
  static const double radiusFull = 999.0;

  // Spacing
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;

  // Header bounds for mobile density
  static const double mobileMaxHeaderHeight = 110.0;
}
