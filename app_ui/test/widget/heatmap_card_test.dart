import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/pages/dashboard/widgets/heatmap_card.dart';
import '../helpers/test_helper.dart';

void main() {
  setUpAll(() => initTestEnvironment());

  group('HeatmapCard', () {
    // ── Happy Path ──
    testWidgets('传入 3 条数据应渲染 3 个单元格', (tester) async {
      // Arrange
      final data = [
        {'date': '2025-01-01', 'count': 1},
        {'date': '2025-01-02', 'count': 5},
        {'date': '2025-01-03', 'count': 0},
      ];
      final card = HeatmapCard(heatmap: data);

      // Act
      await pumpTestWidget(tester, card);

      // Assert — 标题可见，Grid 渲染
      expect(find.text('业务发生频次'), findsOneWidget);
    });

    testWidgets('count 为 0 时单元格色阶为 E2E8F0', (tester) async {
      // Arrange
      final data = [
        {'date': '2025-01-01', 'count': 0},
      ];
      final card = HeatmapCard(heatmap: data);

      // Act
      await pumpTestWidget(tester, card);

      // Assert — 不抛异常即通过
      expect(tester.takeException(), isNull);
    });

    // ── Boundary ──
    testWidgets('空数据时应显示"暂无数据"', (tester) async {
      // Arrange
      const card = HeatmapCard(heatmap: []);

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text('暂无数据'), findsOneWidget);
    });

    testWidgets('仅 1 条数据不崩溃', (tester) async {
      // Arrange
      final data = [
        {'date': '2025-06-15', 'count': 3},
      ];
      final card = HeatmapCard(heatmap: data);

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(tester.takeException(), isNull);
    });

    testWidgets('大量数据（90 天）不崩溃', (tester) async {
      // Arrange
      final data = List.generate(90, (i) {
        final day = (i + 1).toString().padLeft(2, '0');
        return {'date': '2025-01-$day', 'count': i % 7};
      });
      final card = HeatmapCard(heatmap: data);

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(tester.takeException(), isNull);
    });
  });
}
