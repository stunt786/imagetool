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
  });

  final String savePath;
  final bool isLoading;

  AppSettingsState copyWith({
    String? savePath,
    bool? isLoading,
  }) {
    return AppSettingsState(
      savePath: savePath ?? this.savePath,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  static const String _key = 'custom_save_path';

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
    state = AppSettingsState(savePath: path, isLoading: false);
  }

  Future<void> setSavePath(String savePath) async {
    state = state.copyWith(isLoading: true);
    await AppSettingsState.persistPath(savePath);
    state = AppSettingsState(savePath: savePath, isLoading: false);
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
