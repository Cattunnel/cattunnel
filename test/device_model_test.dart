import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/domain/device_model.dart';

void main() {
  test('Android reads only vendor and model', () async {
    expect(
      await DeviceModel.read(
        os: 'android',
        android: () async => {
          'manufacturer': 'Google',
          'model': 'Pixel',
          'serial': 'SECRET',
          'device': 'PRIVATE',
        },
      ),
      'Google Pixel',
    );
  });
  test('Linux reads only DMI vendor and product', () async {
    final paths = <String>[];
    expect(
      await DeviceModel.read(
        os: 'linux',
        file: (path) async {
          paths.add(path);
          return path.endsWith('sys_vendor') ? 'Dell\n' : 'XPS\n';
        },
      ),
      'Dell XPS',
    );
    expect(paths, ['/sys/class/dmi/id/sys_vendor', '/sys/class/dmi/id/product_name']);
  });
  test('Windows reads only vendor and product from the BIOS key', () async {
    final asked = <String>[];
    expect(
      await DeviceModel.read(
        os: 'windows',
        registry: (key, name) {
          expect(key, r'HARDWARE\DESCRIPTION\System\BIOS');
          asked.add(name);
          return 'Test';
        },
      ),
      'Test Test',
    );
    expect(asked, ['SystemManufacturer', 'SystemProductName']);
  });
  test('model is printable ASCII and at most 64 characters', () async {
    final model = await DeviceModel.read(os: 'linux', file: (_) async => 'A\r\n\u0000é${'B' * 100}');
    expect(model.length, 64);
    expect(RegExp(r'^[\x20-\x7e]*$').hasMatch(model), isTrue);
  });
  test('errors produce empty model', () async {
    expect(await DeviceModel.read(os: 'linux', file: (_) async => throw StateError('DMI')), '');
    expect(await DeviceModel.read(os: 'android', android: () async => throw StateError('channel')), '');
    expect(await DeviceModel.read(os: 'windows', registry: (_, _) => null), '');
  });
}
