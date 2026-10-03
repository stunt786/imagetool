// ignore_for_file: depend_on_referenced_packages, unnecessary_import

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;
}

Future<AppSettingsState> _waitForLoad(AppSettingsNotifier notifier) async {
  for (var i = 0; i < 200; i++) {
    if (!notifier.state.isLoading) return notifier.state;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  return notifier.state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform initialPathProvider;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    initialPathProvider = PathProviderPlatform.instance;
    tempDir = await Directory.systemTemp.createTemp('app_settings_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = initialPathProvider;
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('AppSettingsState defaults', () {
    test('every setting ships with the documented default', () {
      const settings = AppSettingsState(savePath: '/storage/PixelTools');

      expect(settings.savePath, '/storage/PixelTools');
      expect(settings.isLoading, isFalse);
      expect(settings.oneClickOpen, isFalse);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.stripExif, isTrue);
      expect(settings.hasCompletedOnboarding, isFalse);
      expect(settings.enableGlobalWatermark, isTrue);
      expect(settings.useWatermarkLogo, isTrue);
      expect(settings.useImageVerticalSidebar, isTrue);
      expect(settings.watermarkText, 'PixelTools');
      expect(settings.watermarkColorHex, 0xFFFFFFFF);
      expect(settings.watermarkOpacity, 0.7);
      expect(settings.watermarkPositionIndex, 4);
    });

    test('legacy getters mirror the stored hex/index values', () {
      const settings = AppSettingsState(
        savePath: '',
        watermarkColorHex: 0xFF112233,
        watermarkPositionIndex: 2,
      );
      expect(settings.watermarkColor, 0xFF112233);
      expect(settings.watermarkPosition, 2);
    });

    test('copyWith only touches the fields that are passed', () {
      const base = AppSettingsState(
        savePath: '/a',
        themeMode: ThemeMode.light,
        stripExif: true,
        oneClickOpen: true,
      );

      final updated = base.copyWith(
        savePath: '/b',
        themeMode: ThemeMode.dark,
        watermarkText: 'Hi',
      );

      expect(updated.savePath, '/b');
      expect(updated.themeMode, ThemeMode.dark);
      expect(updated.watermarkText, 'Hi');
      // untouched fields survive
      expect(updated.stripExif, isTrue);
      expect(updated.oneClickOpen, isTrue);
      expect(updated.hasCompletedOnboarding, isFalse);
    });
  });

  group('AppSettingsState.loadPath', () {
    test('reuses a stored path and creates it when missing', () async {
      final stored = '${tempDir.path}/custom/destination';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'custom_save_path': stored,
      });

      final resolved = await AppSettingsState.loadPath();
      expect(resolved, stored);
      expect(Directory(stored).existsSync(), isTrue);
    });

    test('falls back to <documents>/PixelTools when nothing is stored',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final resolved = await AppSettingsState.loadPath();
      expect(resolved, '${tempDir.path}${Platform.pathSeparator}PixelTools');
      expect(Directory(resolved).existsSync(), isTrue);
    });
  });

  group('AppSettingsState.loadInitial', () {
    test('returns defaults when preferences are empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      final loaded = await AppSettingsState.loadInitial(prefs);
      expect(loaded.isLoading, isFalse);
      expect(loaded.themeMode, ThemeMode.system);
      expect(loaded.stripExif, isTrue);
      expect(loaded.hasCompletedOnboarding, isFalse);
      expect(loaded.oneClickOpen, isFalse);
      expect(loaded.watermarkText, 'PixelTools');
      expect(loaded.watermarkOpacity, 0.7);
      expect(loaded.watermarkPositionIndex, 4);
      expect(loaded.watermarkColorHex, 0xFFFFFFFF);
    });

    test('reads every stored key and clamps an out-of-range theme index',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'one_click_open': true,
        'theme_mode': 99,
        'strip_exif': false,
        'completed_onboarding': true,
        'enable_global_watermark': false,
        'use_watermark_logo': false,
        'use_image_vertical_sidebar': false,
        'watermark_text': 'Trip 2026',
        'watermark_color_hex': 0xFF00FF00,
        'watermark_opacity': 0.25,
        'watermark_position_index': 3,
        'custom_save_path': '/tmp/pixeltools-stored',
      });
      final prefs = await SharedPreferences.getInstance();

      final loaded = await AppSettingsState.loadInitial(prefs);
      expect(loaded.oneClickOpen, isTrue);
      expect(loaded.themeMode, ThemeMode.values.last,
          reason: 'index 99 must clamp to the last ThemeMode');
      expect(loaded.stripExif, isFalse);
      expect(loaded.hasCompletedOnboarding, isTrue);
      expect(loaded.enableGlobalWatermark, isFalse);
      expect(loaded.useWatermarkLogo, isFalse);
      expect(loaded.useImageVerticalSidebar, isFalse);
      expect(loaded.watermarkText, 'Trip 2026');
      expect(loaded.watermarkColorHex, 0xFF00FF00);
      expect(loaded.watermarkOpacity, 0.25);
      expect(loaded.watermarkPositionIndex, 3);
      expect(loaded.savePath, '/tmp/pixeltools-stored');
    });

    test('migrates the legacy "◈ PixelTools" watermark text', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'watermark_text': '◈ PixelTools',
      });
      final prefs = await SharedPreferences.getInstance();

      final loaded = await AppSettingsState.loadInitial(prefs);
      expect(loaded.watermarkText, 'PixelTools');
    });
  });

  group('persist/load round trips', () {
    test('one-click, theme and strip-EXIF survive a reload', () async {
      await AppSettingsState.persistOneClick(true);
      await AppSettingsState.persistThemeMode(ThemeMode.dark);
      await AppSettingsState.persistStripExif(false);

      expect(await AppSettingsState.loadOneClick(), isTrue);
      expect(await AppSettingsState.loadThemeMode(), ThemeMode.dark);
      expect(await AppSettingsState.loadStripExif(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('one_click_open'), isTrue);
      expect(prefs.getInt('theme_mode'), ThemeMode.dark.index);
      expect(prefs.getBool('strip_exif'), isFalse);
    });

    test('onboarding flag round-trips', () async {
      expect(await AppSettingsState.loadCompletedOnboarding(), isFalse);
      await AppSettingsState.persistCompletedOnboarding(true);
      expect(await AppSettingsState.loadCompletedOnboarding(), isTrue);
    });

    test('every watermark setting round-trips', () async {
      await AppSettingsState.persistEnableGlobalWatermark(false);
      await AppSettingsState.persistUseWatermarkLogo(false);
      await AppSettingsState.persistUseImageVerticalSidebar(false);
      await AppSettingsState.persistWatermarkText('Sunset');
      await AppSettingsState.persistWatermarkColorHex(0xFF123456);
      await AppSettingsState.persistWatermarkOpacity(0.35);
      await AppSettingsState.persistWatermarkPositionIndex(1);

      expect(await AppSettingsState.loadEnableGlobalWatermark(), isFalse);
      expect(await AppSettingsState.loadUseWatermarkLogo(), isFalse);
      expect(await AppSettingsState.loadUseImageVerticalSidebar(), isFalse);
      expect(await AppSettingsState.loadWatermarkText(), 'Sunset');
      expect(await AppSettingsState.loadWatermarkColorHex(), 0xFF123456);
      expect(await AppSettingsState.loadWatermarkOpacity(), 0.35);
      expect(await AppSettingsState.loadWatermarkPositionIndex(), 1);
    });

    test('storing an empty watermark text still loads the default brand',
        () async {
      await AppSettingsState.persistWatermarkText('');
      expect(await AppSettingsState.loadWatermarkText(), 'PixelTools');
    });

    test('persistPath stores the path and creates the directory', () async {
      final target = '${tempDir.path}/exports/2026';
      await AppSettingsState.persistPath(target);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('custom_save_path'), target);
      expect(Directory(target).existsSync(), isTrue);
      expect(await AppSettingsState.loadPath(), target);
    });
  });

  group('AppSettingsNotifier', () {
    test('an explicit initial state skips the async load', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'theme_mode': ThemeMode.dark.index,
      });

      final notifier =
          AppSettingsNotifier(const AppSettingsState(savePath: '/given'));
      addTearDown(notifier.dispose);

      expect(notifier.state.savePath, '/given');
      expect(notifier.state.isLoading, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifier.state.themeMode, ThemeMode.system,
          reason: 'the constructor must not overwrite an explicit state');
    });

    test('the default constructor loads persisted values and clears the '
        'loading flag', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'one_click_open': true,
        'strip_exif': false,
        'watermark_text': 'Loaded',
        'theme_mode': ThemeMode.light.index,
      });

      final notifier = AppSettingsNotifier();
      addTearDown(notifier.dispose);
      expect(notifier.state.isLoading, isTrue,
          reason: 'loading starts out true');

      final loaded = await _waitForLoad(notifier);
      expect(loaded.isLoading, isFalse);
      expect(loaded.oneClickOpen, isTrue);
      expect(loaded.stripExif, isFalse);
      expect(loaded.watermarkText, 'Loaded');
      expect(loaded.themeMode, ThemeMode.light);
      expect(loaded.savePath, isNotEmpty);
    });

    test('setSavePath flips isLoading, persists and updates state', () async {
      final notifier = AppSettingsNotifier(const AppSettingsState(savePath: ''));
      addTearDown(notifier.dispose);

      final target = '${tempDir.path}/new-output';
      final pending = notifier.setSavePath(target);
      expect(notifier.state.isLoading, isTrue);
      await pending;

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.savePath, target);
      expect(Directory(target).existsSync(), isTrue);
      expect(await AppSettingsState.loadPath(), target);
    });

    test('each setter updates state and the matching preference', () async {
      final notifier = AppSettingsNotifier(const AppSettingsState(savePath: ''));
      addTearDown(notifier.dispose);

      await notifier.setOneClickOpen(true);
      await notifier.setThemeMode(ThemeMode.dark);
      await notifier.setStripExif(false);
      await notifier.setCompletedOnboarding(true);
      await notifier.setEnableGlobalWatermark(false);
      await notifier.setUseWatermarkLogo(false);
      await notifier.setUseImageVerticalSidebar(false);
      await notifier.setWatermarkText('Holiday');
      await notifier.setWatermarkColorHex(0xFFAA0000);
      await notifier.setWatermarkOpacity(0.42);
      await notifier.setWatermarkPositionIndex(0);

      final state = notifier.state;
      expect(state.oneClickOpen, isTrue);
      expect(state.themeMode, ThemeMode.dark);
      expect(state.stripExif, isFalse);
      expect(state.hasCompletedOnboarding, isTrue);
      expect(state.enableGlobalWatermark, isFalse);
      expect(state.useWatermarkLogo, isFalse);
      expect(state.useImageVerticalSidebar, isFalse);
      expect(state.watermarkText, 'Holiday');
      expect(state.watermarkColorHex, 0xFFAA0000);
      expect(state.watermarkOpacity, 0.42);
      expect(state.watermarkPositionIndex, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('one_click_open'), isTrue);
      expect(prefs.getInt('theme_mode'), ThemeMode.dark.index);
      expect(prefs.getBool('strip_exif'), isFalse);
      expect(prefs.getBool('completed_onboarding'), isTrue);
      expect(prefs.getBool('enable_global_watermark'), isFalse);
      expect(prefs.getBool('use_watermark_logo'), isFalse);
      expect(prefs.getBool('use_image_vertical_sidebar'), isFalse);
      expect(prefs.getString('watermark_text'), 'Holiday');
      expect(prefs.getInt('watermark_color_hex'), 0xFFAA0000);
      expect(prefs.getDouble('watermark_opacity'), 0.42);
      expect(prefs.getInt('watermark_position_index'), 0);
    });

    test('getSaveDirectory creates a missing explicit path', () async {
      final target = '${tempDir.path}/made/on/demand';
      final notifier = AppSettingsNotifier(
        AppSettingsState(savePath: target),
      );
      addTearDown(notifier.dispose);

      final dir = await notifier.getSaveDirectory();
      expect(dir.path, target);
      expect(dir.existsSync(), isTrue);
    });

    test('getSaveDirectory falls back to loadPath when savePath is empty',
        () async {
      final notifier = AppSettingsNotifier(
        const AppSettingsState(savePath: ''),
      );
      addTearDown(notifier.dispose);

      final dir = await notifier.getSaveDirectory();
      expect(dir.path, '${tempDir.path}${Platform.pathSeparator}PixelTools');
      expect(dir.existsSync(), isTrue);
    });

    test('the provider exposes a notifier driven by persisted settings',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'theme_mode': ThemeMode.dark.index,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(appSettingsProvider);
      AppSettingsState state;
      for (var i = 0; i < 200; i++) {
        state = container.read(appSettingsProvider);
        if (!state.isLoading) break;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      state = container.read(appSettingsProvider);
      expect(state.isLoading, isFalse);
      expect(state.themeMode, ThemeMode.dark);

      await container.read(appSettingsProvider.notifier).setStripExif(false);
      expect(container.read(appSettingsProvider).stripExif, isFalse);
    });
  });
}
