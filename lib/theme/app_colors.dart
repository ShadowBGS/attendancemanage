import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Light Mode Colors
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color secondaryBlue = Color(0xFF1976D2);
  static const Color background = Color(0xFFF5F5F5);
  static const Color avatarBg = Color(0xFFFFDBC1);
  static const Color avatarIcon = Color(0xFF8B5A3C);
  static const Color errorRed = Color(0xFFE53935);
  static const Color successGreen = Color(0xFF4CAF50);

  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color grey = Colors.grey;
}

class AppColorsDark {
  AppColorsDark._();

  // Dark Mode Colors
  static const Color primaryBlue = Color(0xFF42A5F5);
  static const Color secondaryBlue = Color(0xFF64B5F6);
  static const Color background = Color(0xFF121212);
  static const Color avatarBg = Color(0xFF1F1F1F);
  static const Color avatarIcon = Color(0xFFBBBBBB);

  static const Color white = Color(0xFFFAFAFA);
  static const Color black = Color(0xFF121212);
  static const Color grey = Color(0xFF888888);
}

/// Helper class to get colors based on current theme
class ThemeColors {
  ThemeColors._();
  
  /// Get the appropriate color set based on brightness
  static Color getPrimaryColor(Brightness brightness) {
    return brightness == Brightness.dark 
      ? AppColorsDark.primaryBlue 
      : AppColors.primaryBlue;
  }

  static Color getSecondaryColor(Brightness brightness) {
    return brightness == Brightness.dark 
      ? AppColorsDark.secondaryBlue 
      : AppColors.secondaryBlue;
  }

  static Color getBackgroundColor(Brightness brightness) {
    return brightness == Brightness.dark 
      ? AppColorsDark.background 
      : AppColors.background;
  }

  static Color getAvatarBgColor(Brightness brightness) {
    return brightness == Brightness.dark 
      ? AppColorsDark.avatarBg 
      : AppColors.avatarBg;
  }

  static Color getAvatarIconColor(Brightness brightness) {
    return brightness == Brightness.dark 
      ? AppColorsDark.avatarIcon 
      : AppColors.avatarIcon;
  }
}
