import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettingsState {
  const AppSettingsState({
    required this.savePath,
    this.isLoading = false,
    this.oneClickOpen = false,
    this.themeMode = ThemeMode.system,
    this.stripExif = true,
    this.hasCompletedOnboarding = false,
    this.enableGlobalWatermark = false,
    this.watermarkText = '© PixelTools',
    this.watermarkColorHex = 0xFFFFFFFF,
    this.watermarkOpacity = 0.7,
    this.watermarkPositionIndex = 4,
  });

  final String savePath;
  final bool isLoading;
  final bool oneClickOpen;
  final ThemeMode themeMode;
  final bool stripExif;
  final bool hasCompletedOnboarding;
  final bool enableGlobalWatermark;
  final String watermarkText;
  final int watermarkColorHex;
  final double watermarkOpacity;
  final int watermarkPositionIndex;

  AppSettingsState copyWith({
    String? savePath,
    bool? isLoading,
    bool? oneClickOpen,
    ThemeMode? themeMode,
    bool? stripExif,
    bool? hasCompletedOnboarding,
    bool? enableGlobalWatermark,
    String? watermarkText,
    int? watermarkColorHex,
    double? watermarkOpacity,
    int? watermarkPositionIndex,
  }) {
    return AppSettingsState(
      savePath: savePath ?? this.savePath,
      isLoading: isLoading ?? this.isLoading,
      oneClickOpen: oneClickOpen ?? this.oneClickOpen,
      themeMode: themeMode ?? this.themeMode,
      stripExif: stripExif ?? this.stripExif,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      enableGlobalWatermark:
          enableGlobalWatermark ?? this.enableGlobalWatermark,
      watermarkText: watermarkText ?? this.watermarkText,
      watermarkColorHex: watermarkColorHex ?? this.watermarkColorHex,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
      watermarkPositionIndex:
          watermarkPositionIndex ?? this.watermarkPositionIndex,
    );
  }

  static const String _key = 'custom_save_path';
  static const String _oneClickKey = 'one_click_open';
  static const String _themeModeKey = 'theme_mode';
  static const String _stripExifKey = 'strip_exif';
  static const String _completedOnboardingKey = 'completed_onboarding';
  static const String _enableGlobalWatermarkKey = 'enable_global_watermark';
  static const String _watermarkTextKey = 'watermark_text';
  static const String _watermarkColorHexKey = 'watermark_color_hex';
  static const String _watermarkOpacityKey = 'watermark_opacity';
  static const String _watermarkPositionIndexKey = 'watermark_position_index';

  static Future<String> loadPath() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored != null && stored.isNotEmpty) return stored;
    final docsDir = await getApplicationDocumentsDirectory();
    final defaultDir = Directory(path.join(docsDir.path, 'pixeltools'));
    if (!await defaultDir.exists()) {
      await defaultDir.create(recursive: true);
    }
    return defaultDir.path;
  }

  static Future<void> persistPath(String savePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, savePath);
    final dir = Directory(savePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  static Future<bool> loadOneClick() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_oneClickKey) ?? false;
  }

  static Future<void> persistOneClick(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_oneClickKey, value);
  }

  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_themeModeKey) ?? 0;
    return ThemeMode.values[index.clamp(0, ThemeMode.values.length - 1)];
  }

  static Future<void> persistThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  static Future<bool> loadStripExif() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_stripExifKey) ?? true;
  }

  static Future<void> persistStripExif(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stripExifKey, value);
  }

  static Future<bool> loadCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedOnboardingKey) ?? false;
  }

  static Future<void> persistCompletedOnboarding(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedOnboardingKey, value);
  }

  static Future<bool> loadEnableGlobalWatermark() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableGlobalWatermarkKey) ?? false;
  }

  static Future<void> persistEnableGlobalWatermark(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableGlobalWatermarkKey, value);
  }

  static Future<String> loadWatermarkText() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_watermarkTextKey) ?? '© PixelTools';
  }

  static Future<void> persistWatermarkText(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_watermarkTextKey, value);
  }

  static Future<int> loadWatermarkColorHex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_watermarkColorHexKey) ?? 0xFFFFFFFF;
  }

  static Future<void> persistWatermarkColorHex(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_watermarkColorHexKey, value);
  }

  static Future<double> loadWatermarkOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_watermarkOpacityKey) ?? 0.7;
  }

  static Future<void> persistWatermarkOpacity(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_watermarkOpacityKey, value);
  }

  static Future<int> loadWatermarkPositionIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_watermarkPositionIndexKey) ?? 4;
  }

  static Future<void> persistWatermarkPositionIndex(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_watermarkPositionIndexKey, value);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>(
  (ref) => AppSettingsNotifier(),
);

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier() : super(const AppSettingsState(savePath: '')) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final savePath = await AppSettingsState.loadPath();
    final oneClick = await AppSettingsState.loadOneClick();
    final themeMode = await AppSettingsState.loadThemeMode();
    final stripExif = await AppSettingsState.loadStripExif();
    final completedOnboarding = await AppSettingsState.loadCompletedOnboarding();
    final enableGlobalWatermark =
        await AppSettingsState.loadEnableGlobalWatermark();
    final watermarkText = await AppSettingsState.loadWatermarkText();
    final watermarkColorHex = await AppSettingsState.loadWatermarkColorHex();
    final watermarkOpacity = await AppSettingsState.loadWatermarkOpacity();
    final watermarkPositionIndex =
        await AppSettingsState.loadWatermarkPositionIndex();
    state = AppSettingsState(
      savePath: savePath,
      isLoading: false,
      oneClickOpen: oneClick,
      themeMode: themeMode,
      stripExif: stripExif,
      hasCompletedOnboarding: completedOnboarding,
      enableGlobalWatermark: enableGlobalWatermark,
      watermarkText: watermarkText,
      watermarkColorHex: watermarkColorHex,
      watermarkOpacity: watermarkOpacity,
      watermarkPositionIndex: watermarkPositionIndex,
    );
  }

  Future<void> setSavePath(String savePath) async {
    state = state.copyWith(isLoading: true);
    await AppSettingsState.persistPath(savePath);
    state = state.copyWith(savePath: savePath, isLoading: false);
  }

  Future<void> setOneClickOpen(bool value) async {
    await AppSettingsState.persistOneClick(value);
    state = state.copyWith(oneClickOpen: value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await AppSettingsState.persistThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setStripExif(bool value) async {
    await AppSettingsState.persistStripExif(value);
    state = state.copyWith(stripExif: value);
  }

  Future<void> setCompletedOnboarding(bool value) async {
    await AppSettingsState.persistCompletedOnboarding(value);
    state = state.copyWith(hasCompletedOnboarding: value);
  }

  Future<void> setEnableGlobalWatermark(bool value) async {
    await AppSettingsState.persistEnableGlobalWatermark(value);
    state = state.copyWith(enableGlobalWatermark: value);
  }

  Future<void> setWatermarkText(String value) async {
    await AppSettingsState.persistWatermarkText(value);
    state = state.copyWith(watermarkText: value);
  }

  Future<void> setWatermarkColorHex(int value) async {
    await AppSettingsState.persistWatermarkColorHex(value);
    state = state.copyWith(watermarkColorHex: value);
  }

  Future<void> setWatermarkOpacity(double value) async {
    await AppSettingsState.persistWatermarkOpacity(value);
    state = state.copyWith(watermarkOpacity: value);
  }

  Future<void> setWatermarkPositionIndex(int value) async {
    await AppSettingsState.persistWatermarkPositionIndex(value);
    state = state.copyWith(watermarkPositionIndex: value);
  }

  Future<Directory> getSaveDirectory() async {
    final savePath = state.savePath.isEmpty
        ? await AppSettingsState.loadPath()
        : state.savePath;
    final dir = Directory(savePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
