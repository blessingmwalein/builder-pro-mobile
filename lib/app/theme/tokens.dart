import 'package:flutter/animation.dart';

/// Spacing scale (4-pt grid). Never hard-code paddings in screens.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3 = 32;
  static const double x4 = 40;
  static const double x5 = 56;

  /// Horizontal page gutter on phones.
  static const double gutter = 16;
}

/// Corner radii. The web brand uses a 10px base radius.
abstract final class Corners {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;

  /// Cards and card-like tiles: rounder than buttons and fields.
  static const double card = 16;
}

/// Interaction sizes. Field crews wear gloves, so frequent controls are large.
abstract final class Sizes {
  static const double touchTarget = 48;
  static const double buttonHeight = 52;
  static const double buttonHeightCompact = 40;
  static const double inputHeight = 52;
  static const double bottomBarHeight = 68;
  static const double iconSm = 18;
  static const double iconMd = 22;
  static const double iconLg = 28;
  static const double iconContainer = 40;
  static const double clockButton = 168;
  static const double maxContentWidth = 640;
  static const double borderWidth = 1;

  /// A card's outline: thinner than a field's, so cards sit softly on the page.
  static const double cardBorderWidth = 0.75;
}

/// Motion tokens.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
}
