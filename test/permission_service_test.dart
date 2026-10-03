// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'package:pixeltools/core/services/permission_service.dart';

/// Hand-written fake: every status the service can observe is scripted per
/// [Permission], and every [request] is recorded.
class FakePermissionHandler extends PermissionHandlerPlatform {
  FakePermissionHandler({
    Map<ph.Permission, ph.PermissionStatus>? statuses,
    Map<ph.Permission, ph.PermissionStatus>? requestResults,
  })  : statuses = statuses ?? <ph.Permission, ph.PermissionStatus>{},
        requestResults = requestResults ?? <ph.Permission, ph.PermissionStatus>{};

  final Map<ph.Permission, ph.PermissionStatus> statuses;
  final Map<ph.Permission, ph.PermissionStatus> requestResults;
  final List<ph.Permission> requested = <ph.Permission>[];
  final List<ph.Permission> checked = <ph.Permission>[];
  int openSettingsCalls = 0;

  @override
  Future<ph.PermissionStatus> checkPermissionStatus(ph.Permission permission) async {
    checked.add(permission);
    return statuses[permission] ?? ph.PermissionStatus.denied;
  }

  @override
  Future<Map<ph.Permission, ph.PermissionStatus>> requestPermissions(
    List<ph.Permission> permissions,
  ) async {
    final results = <ph.Permission, ph.PermissionStatus>{};
    for (final permission in permissions) {
      requested.add(permission);
      results[permission] = requestResults[permission] ?? ph.PermissionStatus.denied;
    }
    return results;
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalls++;
    return true;
  }
}

void main() {
  late PermissionHandlerPlatform initialInstance;

  setUp(() {
    initialInstance = PermissionHandlerPlatform.instance;
  });

  tearDown(() {
    PermissionHandlerPlatform.instance = initialInstance;
  });

  FakePermissionHandler install(FakePermissionHandler fake) {
    PermissionHandlerPlatform.instance = fake;
    return fake;
  }

  group('photoAccessLevel', () {
    test('granted maps to full access', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.granted,
        },
      ));
      expect(await const AppPermissionService().photoAccessLevel(),
          PhotoAccess.full);
    });

    test('limited ("selected photos") maps to limited access', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.limited,
        },
      ));
      expect(await const AppPermissionService().photoAccessLevel(),
          PhotoAccess.limited);
    });

    test('anything else maps to no access', () async {
      for (final status in <ph.PermissionStatus>[
        ph.PermissionStatus.denied,
        ph.PermissionStatus.restricted,
        ph.PermissionStatus.permanentlyDenied,
        ph.PermissionStatus.provisional,
      ]) {
        install(FakePermissionHandler(
          statuses: <ph.Permission, ph.PermissionStatus>{
            ph.Permission.photos: status,
          },
        ));
        expect(await const AppPermissionService().photoAccessLevel(),
            PhotoAccess.none,
            reason: 'status $status should not grant access');
      }
    });
  });

  group('hasStoragePermission', () {
    test('is true as soon as photo access is usable', () async {
      final fake = install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.limited,
        },
      ));
      expect(await const AppPermissionService().hasStoragePermission(), isTrue);
      expect(fake.checked, <ph.Permission>[ph.Permission.photos],
          reason: 'storage is not consulted once photos are usable');
    });

    test('falls back to the legacy storage permission', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.denied,
          ph.Permission.storage: ph.PermissionStatus.granted,
        },
      ));
      expect(await const AppPermissionService().hasStoragePermission(), isTrue);
    });

    test('is false when both permissions are denied', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.denied,
          ph.Permission.storage: ph.PermissionStatus.denied,
        },
      ));
      expect(await const AppPermissionService().hasStoragePermission(), isFalse);
    });
  });

  group('requestStoragePermission', () {
    test('stops at photos when they are already granted', () async {
      final fake = install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.granted,
        },
      ));
      expect(
          await const AppPermissionService().requestStoragePermission(), isTrue);
      expect(fake.requested, isEmpty);
    });

    test('requests photos once and reports the granted result', () async {
      final fake = install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.denied,
        },
        requestResults: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.granted,
        },
      ));
      expect(
          await const AppPermissionService().requestStoragePermission(), isTrue);
      expect(fake.requested, <ph.Permission>[ph.Permission.photos]);
    });

    test('a limited photos grant counts as a successful import permission',
        () async {
      final fake = install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.denied,
        },
        requestResults: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.limited,
        },
      ));
      expect(
          await const AppPermissionService().requestStoragePermission(), isTrue);
      expect(fake.requested, <ph.Permission>[ph.Permission.photos]);
    });

    test('falls back to the legacy storage request when photos are denied',
        () async {
      final fake = install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.denied,
          ph.Permission.storage: ph.PermissionStatus.denied,
        },
        requestResults: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.denied,
          ph.Permission.storage: ph.PermissionStatus.granted,
        },
      ));
      expect(
          await const AppPermissionService().requestStoragePermission(), isTrue);
      expect(fake.requested,
          <ph.Permission>[ph.Permission.photos, ph.Permission.storage]);
    });

    test('never re-prompts for a permanently denied photos permission',
        () async {
      final fake = install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.permanentlyDenied,
          ph.Permission.storage: ph.PermissionStatus.granted,
        },
      ));
      expect(
          await const AppPermissionService().requestStoragePermission(), isTrue);
      expect(fake.requested, isEmpty,
          reason: 'permanently denied permissions must not be re-requested');
    });

    test('returns false when every request is refused', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.denied,
          ph.Permission.storage: ph.PermissionStatus.denied,
        },
        requestResults: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.denied,
          ph.Permission.storage: ph.PermissionStatus.denied,
        },
      ));
      expect(
          await const AppPermissionService().requestStoragePermission(), isFalse);
    });

    test('a restricted photos status triggers a request too', () async {
      final fake = install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.restricted,
        },
        requestResults: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.granted,
        },
      ));
      expect(
          await const AppPermissionService().requestStoragePermission(), isTrue);
      expect(fake.requested, <ph.Permission>[ph.Permission.photos]);
    });
  });

  group('permanently denied / camera / settings', () {
    test('reports a permanently denied photos permission', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.permanentlyDenied,
          ph.Permission.storage: ph.PermissionStatus.granted,
        },
      ));
      expect(
          await const AppPermissionService().isStoragePermissionPermanentlyDenied(),
          isTrue);
    });

    test('reports a permanently denied legacy storage permission', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.granted,
          ph.Permission.storage: ph.PermissionStatus.permanentlyDenied,
        },
      ));
      expect(
          await const AppPermissionService().isStoragePermissionPermanentlyDenied(),
          isTrue);
    });

    test('is not permanently denied when access is usable', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.photos: ph.PermissionStatus.granted,
          ph.Permission.storage: ph.PermissionStatus.denied,
        },
      ));
      expect(
          await const AppPermissionService().isStoragePermissionPermanentlyDenied(),
          isFalse);
    });

    test('camera access follows the camera permission only', () async {
      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.camera: ph.PermissionStatus.granted,
          ph.Permission.photos: ph.PermissionStatus.denied,
        },
      ));
      expect(await const AppPermissionService().hasCameraPermission(), isTrue);

      install(FakePermissionHandler(
        statuses: <ph.Permission, ph.PermissionStatus>{
          ph.Permission.camera: ph.PermissionStatus.denied,
        },
      ));
      expect(await const AppPermissionService().hasCameraPermission(), isFalse);
    });

    test('openAppSettings delegates to the platform implementation', () async {
      final fake = install(FakePermissionHandler());
      await const AppPermissionService().openAppSettings();
      expect(fake.openSettingsCalls, 1);
    });
  });
}
