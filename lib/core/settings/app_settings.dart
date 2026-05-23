import 'dart:io';

import 'package:flutter/foundation.dart';
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
  });

  final String savePath;
  final bool isLoading;
  final bool oneClickOpen;

  AppSettingsState copyWith({
    String? savePath,
    bool? isLoading,
    bool? oneClickOpen,
  }) {
    return AppSettingsState(
      savePath: savePath ?? this.savePath,
      isLoading: isLoading ?? this.isLoading,
      oneClickOpen: oneClickOpen ?? this.oneClickOpen,
    );
  }

  static const String _key = 'custom_save_path';
  static const String _oneClickKey = 'one_click_open';

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
    final path = await AppSettingsState.loadPath();
    final oneClick = await AppSettingsState.loadOneClick();
    state = AppSettingsState(savePath: path, isLoading: false, oneClickOpen: oneClick);
  }

  Future<void> setSavePath(String savePath) async {
    state = state.copyWith(isLoading: true);
    await AppSettingsState.persistPath(savePath);
    state = AppSettingsState(savePath: savePath, isLoading: false, oneClickOpen: state.oneClickOpen);
  }

  Future<void> setOneClickOpen(bool value) async {
    await AppSettingsState.persistOneClick(value);
    state = state.copyWith(oneClickOpen: value);
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
