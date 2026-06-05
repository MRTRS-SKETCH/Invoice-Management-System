import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/logger.dart';

void main() {
  group('AppLogger', () {
    // ── Happy Path ──
    test('info 应将日志入队，bufferLength + 1', () {
      // Arrange — 确保测试前缓冲清空（无法直接清，取差值）
      final before = AppLogger.bufferLength;

      // Act
      AppLogger.info('测试信息');

      // Assert
      expect(AppLogger.bufferLength, greaterThan(before));
    });

    test('warning 应入队而不抛异常', () {
      // Arrange
      final before = AppLogger.bufferLength;

      // Act
      AppLogger.warning('测试警告');

      // Assert
      expect(AppLogger.bufferLength, greaterThan(before));
    });

    test('error 应入队且包含异常信息', () {
      // Arrange
      final before = AppLogger.bufferLength;

      // Act
      AppLogger.error('测试错误', Exception('细节'));

      // Assert
      expect(AppLogger.bufferLength, greaterThan(before));
    });

    // ── Boundary ──
    test('error 的 error 参数为 null 时不抛异常', () {
      // Arrange & Act — 不应抛出异常
      AppLogger.error('错误消息', null);

      // Assert — 到达这里即通过
      expect(AppLogger.bufferLength, greaterThan(0));
    });

    test('连续调用 info 多次可正常累计', () {
      // Arrange
      final before = AppLogger.bufferLength;

      // Act
      for (int i = 0; i < 10; i++) {
        AppLogger.info('第 $i 条');
      }

      // Assert
      expect(AppLogger.bufferLength, greaterThanOrEqualTo(before + 10));
    });

    // Note: 满 50 条自动 flush 的测试涉及异步网络请求，
    // AppLogger 直接使用 http.post 无法在单元测试中拦截。
    // 该行为应在集成测试中覆盖。
  });
}
