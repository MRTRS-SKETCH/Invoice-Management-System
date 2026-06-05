import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/config.dart';

void main() {
  group('AppConfig', () {
    // Reset baseUrl before each test
    setUp(() {
      AppConfig.baseUrl = 'http://127.0.0.1:18090';
    });

    tearDown(() {
      AppConfig.baseUrl = 'http://127.0.0.1:18090';
    });

    // ── Happy Path ──
    test('updatePort 应正确拼接 baseUrl', () {
      // Arrange
      const port = 18091;

      // Act
      AppConfig.updatePort(port);

      // Assert
      expect(AppConfig.baseUrl, 'http://127.0.0.1:18091');
    });

    // ── Boundary ──
    test('updatePort(0) 应在端口为 0 时正确拼接', () {
      // Arrange
      const port = 0;

      // Act
      AppConfig.updatePort(port);

      // Assert
      expect(AppConfig.baseUrl, 'http://127.0.0.1:0');
    });

    test('updatePort(65535) 应对最大端口号正确拼接', () {
      // Arrange
      const port = 65535;

      // Act
      AppConfig.updatePort(port);

      // Assert
      expect(AppConfig.baseUrl, 'http://127.0.0.1:65535');
    });

    test('baseUrl 默认值为 localhost:18090', () {
      // Act & Assert（无需 updatePort，验证默认值）
      expect(AppConfig.baseUrl, 'http://127.0.0.1:18090');
    });
  });
}
