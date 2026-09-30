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
    this.enableGlobalWatermark = true,
    this.useWatermarkLogo = true,
    this.useImageVerticalSidebar = true,
    this.watermarkText = 'PixelTools',
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
  final bool useWatermarkLogo;
  final bool useImageVerticalSidebar;
  final String watermarkText;
  final int watermarkColorHex;
  final double watermarkOpacity;
  final int watermarkPositionIndex;

  int get watermarkColor => watermarkColorHex;
  int get watermarkPosition => watermarkPositionIndex;

  AppSettingsState copyWith({
    String? savePath,
    bool? isLoading,
    bool? oneClickOpen,
    ThemeMode? themeMode,
    bool? stripExif,
    bool? hasCompletedOnboarding,
    bool? enableGlobalWatermark,
    bool? useWatermarkLogo,
    bool? useImageVerticalSidebar,
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
      useWatermarkLogo: useWatermarkLogo ?? this.useWatermarkLogo,
      useImageVerticalSidebar:
          useImageVerticalSidebar ?? this.useImageVerticalSidebar,
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
  static const String _useWatermarkLogoKey = 'use_watermark_logo';
  static const String _useImageVerticalSidebarKey =
      'use_image_vertical_sidebar';
  static const String _watermarkTextKey = 'watermark_text';
  static const String _watermarkColorHexKey = 'watermark_color_hex';
  static const String _watermarkOpacityKey = 'watermark_opacity';
  static const String _watermarkPositionIndexKey = 'watermark_position_index';

  static Future<String> loadPath([SharedPreferences? preferences]) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    // On Android the raw `custom_save_path` is legacy: without
    // MANAGE_EXTERNAL_STORAGE it is no longer writable. The user's destination
    // is the SAF folder from Settings (`custom_save_tree_uri`) plus MediaStore
    // defaults, while tool outputs are staged in the app-private directory.
    if (!Platform.isAndroid) {
      final stored = prefs.getString(_key);
      if (stored != null && stored.isNotEmpty) {
        final storedDir = Directory(stored);
        if (!await storedDir.exists()) {
          try {
            await storedDir.create(recursive: true);
          } catch (_) {}
        }
        return stored;
      }
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final defaultDir = Directory(path.join(docsDir.path, 'PixelTools'));
    if (!await defaultDir.exists()) {
      await defaultDir.create(recursive: true);
    }
    return defaultDir.path;
  }

  static Future<AppSettingsState> loadInitial(SharedPreferences prefs) async {
    final savePath = await loadPath(prefs);
    final oneClick = prefs.getBool(_oneClickKey) ?? false;
    final themeIndex = prefs.getInt(_themeModeKey) ?? 0;
    final themeMode =
        ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
    final stripExif = prefs.getBool(_stripExifKey) ?? true;
    final completedOnboarding =
        prefs.getBool(_completedOnboardingKey) ?? false;
    final enableGlobalWatermark =
        prefs.getBool(_enableGlobalWatermarkKey) ?? true;
    final useWatermarkLogo = prefs.getBool(_useWatermarkLogoKey) ?? true;
    final useImageVerticalSidebar =
        prefs.getBool(_useImageVerticalSidebarKey) ?? true;
    final storedWatermark = prefs.getString(_watermarkTextKey);
    final watermarkText = (storedWatermark == null ||
            storedWatermark.isEmpty ||
            storedWatermark == '◈ PixelTools')
        ? 'PixelTools'
        : storedWatermark;
    final watermarkColorHex =
        prefs.getInt(_watermarkColorHexKey) ?? 0xFFFFFFFF;
    final watermarkOpacity = prefs.getDouble(_watermarkOpacityKey) ?? 0.7;
    final watermarkPositionIndex =
        prefs.getInt(_watermarkPositionIndexKey) ?? 4;

    return AppSettingsState(
      savePath: savePath,
      isLoading: false,
      oneClickOpen: oneClick,
      themeMode: themeMode,
      stripExif: stripExif,
      hasCompletedOnboarding: completedOnboarding,
      enableGlobalWatermark: enableGlobalWatermark,
      useWatermarkLogo: useWatermarkLogo,
      useImageVerticalSidebar: useImageVerticalSidebar,
      watermarkText: watermarkText,
      watermarkColorHex: watermarkColorHex,
      watermarkOpacity: watermarkOpacity,
      watermarkPositionIndex: watermarkPositionIndex,
    );
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
    return prefs.getBool(_enableGlobalWatermarkKey) ?? true;
  }

  static Future<void> persistEnableGlobalWatermark(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableGlobalWatermarkKey, value);
  }

  static Future<bool> loadUseWatermarkLogo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useWatermarkLogoKey) ?? true;
  }

  static Future<void> persistUseWatermarkLogo(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useWatermarkLogoKey, value);
  }

  static Future<bool> loadUseImageVerticalSidebar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useImageVerticalSidebarKey) ?? true;
  }

  static Future<void> persistUseImageVerticalSidebar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useImageVerticalSidebarKey, value);
  }

  static Future<String> loadWatermarkText() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_watermarkTextKey);
    if (stored == null || stored.isEmpty || stored == '◈ PixelTools') {
      return 'PixelTools';
    }
    return stored;
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
  AppSettingsNotifier([AppSettingsState? initial])
      : super(initial ?? const AppSettingsState(savePath: '')) {
    if (initial == null) {
      _load();
    }
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final savePath = await AppSettingsState.loadPath();
    final oneClick = await AppSettingsState.loadOneClick();
    final themeMode = await AppSettingsState.loadThemeMode();
    final stripExif = await AppSettingsState.loadStripExif();
    final completedOnboarding =
        await AppSettingsState.loadCompletedOnboarding();
    final enableGlobalWatermark =
        await AppSettingsState.loadEnableGlobalWatermark();
    final useWatermarkLogo = await AppSettingsState.loadUseWatermarkLogo();
    final useImageVerticalSidebar =
        await AppSettingsState.loadUseImageVerticalSidebar();
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
      useWatermarkLogo: useWatermarkLogo,
      useImageVerticalSidebar: useImageVerticalSidebar,
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

  Future<void> setUseWatermarkLogo(bool value) async {
    await AppSettingsState.persistUseWatermarkLogo(value);
    state = state.copyWith(useWatermarkLogo: value);
  }

  Future<void> setUseImageVerticalSidebar(bool value) async {
    await AppSettingsState.persistUseImageVerticalSidebar(value);
    state = state.copyWith(useImageVerticalSidebar: value);
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

typedef AppSettings = AppSettingsState;

