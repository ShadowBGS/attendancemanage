import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Extension to easily get theme-aware colors in any widget
extension ThemeAwareColors on BuildContext {
  /// Get colors based on current theme brightness
  bool get isDarkMode {
    return Theme.of(this).brightness == Brightness.dark;
  }

  /// Get primary color for current theme
  Color get primaryBlue {
    return isDarkMode ? AppColorsDark.primaryBlue : AppColors.primaryBlue;
  }

  /// Get secondary color for current theme
  Color get secondaryBlue {
    return isDarkMode ? AppColorsDark.secondaryBlue : AppColors.secondaryBlue;
  }

  /// Get background color for current theme
  Color get backgroundColor {
    return isDarkMode ? AppColorsDark.background : AppColors.background;
  }

  /// Get text color for current theme
  Color get textColor {
    return isDarkMode ? AppColorsDark.white : AppColors.black;
  }

  /// Get subtitle/secondary text color
  Color get subtitleColor {
    return isDarkMode ? AppColorsDark.grey : AppColors.grey;
  }

  /// Get white/light color
  Color get lightColor {
    return isDarkMode ? AppColorsDark.white : AppColors.white;
  }

  /// Get black/dark color
  Color get darkColor {
    return isDarkMode ? AppColorsDark.black : AppColors.black;
  }

  /// Get grey color
  Color get greyColor {
    return isDarkMode ? AppColorsDark.grey : AppColors.grey;
  }

  /// Get avatar background
  Color get avatarBg {
    return isDarkMode ? AppColorsDark.avatarBg : AppColors.avatarBg;
  }

  /// Get avatar icon color
  Color get avatarIcon {
    return isDarkMode ? AppColorsDark.avatarIcon : AppColors.avatarIcon;
  }
}
