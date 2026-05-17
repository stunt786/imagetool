import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettingsState {
  const AppSettingsState({
    required this.saveLocation,
    this.isLoading = false,
  });

  final String saveLocation;
  final bool isLoading;

  AppSettingsState copyWith({
    String? saveLocation,
    bool? isLoading,
  }) {
    return AppSettingsState(
      saveLocation: saveLocation ?? this.saveLocation,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  static const String _defaultKey = 'default_save_location';
  static const String _defaultLocation = 'app_documents';

  static Future<String> loadLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultKey) ?? _defaultLocation;
  }

  static Future<void> persistLocation(String location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultKey, location);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>(
  (ref) => AppSettingsNotifier(),
);

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier() : super(const AppSettingsState(saveLocation: '')) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final location = await AppSettingsState.loadLocation();
    state = AppSettingsState(saveLocation: location, isLoading: false);
  }

  Future<void> setSaveLocation(String location) async {
    state = state.copyWith(isLoading: true);
    await AppSettingsState.persistLocation(location);
    state = AppSettingsState(saveLocation: location, isLoading: false);
  }

  Future<Directory> getSaveDirectory() async {
    final location = state.saveLocation.isEmpty
        ? AppSettingsState._defaultLocation
        : state.saveLocation;

    Directory? dir;
    
    switch (location) {
      case 'downloads':
        dir = await getDownloadsDirectory();
        if (dir != null && await _isWritable(dir)) return dir;
        break;
      case 'external':
        dir = await getExternalStorageDirectory();
        if (dir != null && await _isWritable(dir)) return dir;
        break;
    }
    
    return getApplicationDocumentsDirectory();
  }

  Future<bool> _isWritable(Directory dir) async {
    try {
      final testFile = File('${dir.path}/.write_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
