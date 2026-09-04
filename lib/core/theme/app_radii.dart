import 'package:flutter/material.dart';

class AppRadii {
  AppRadii._();

  static const Radius small = Radius.circular(4.0);
  static const Radius medium = Radius.circular(8.0);
  static const Radius large = Radius.circular(16.0);
  static const Radius pill = Radius.circular(999.0);

  static const BorderRadius smallBorder = BorderRadius.all(small);
  static const BorderRadius mediumBorder = BorderRadius.all(medium);
  static const BorderRadius largeBorder = BorderRadius.all(large);
  static const BorderRadius pillBorder = BorderRadius.all(pill);
}
