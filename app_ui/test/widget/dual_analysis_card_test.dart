import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/pages/dashboard/widgets/dual_analysis_card.dart';
import '../helpers/test_helper.dart';

void main() {
  setUpAll(() => initTestEnvironment());

  group('DualAnalysisCard', () {
    // ── Happy Path ──
    testWidgets('有数据时应渲染进度条和环形图', (tester) async {
      // Arrange
      final distribution = [
        {'category': '项目A', 'amount': 5000},
        {'category': '项目B', 'amount': 3000},
        {'category': '项目C', 'amount': 1000},
      ];
      final typeDistribution = [
        {'category': '差旅', 'percentage': 0.6},
        {'category': '办公', 'percentage': 0.4},
      ];

      final card = DualAnalysisCard(
        distribution: distribution,
        typeDistribution: typeDistribution,
        analysisTimeRange: '近30天',
        onTimeRangeChanged: (_) {},
        onDateRangeChanged: (_, __) {},
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text('多维开销分析'), findsOneWidget);
      expect(find.text('项目A'), findsOneWidget);
      expect(find.text('项目B'), findsOneWidget);
    });

    // ── Boundary ──
    testWidgets('空 distribution 时应显示"暂无数据"', (tester) async {
      // Arrange
      final card = DualAnalysisCard(
        distribution: [],
        typeDistribution: [],
        analysisTimeRange: '近30天',
        onTimeRangeChanged: (_) {},
        onDateRangeChanged: (_, __) {},
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text('暂无数据'), findsWidgets); // 左右各一个
    });

    testWidgets('空 typeDistribution 时应显示"暂无数据"', (tester) async {
      // Arrange
      final distribution = [
        {'category': '项目A', 'amount': 5000},
      ];
      final card = DualAnalysisCard(
        distribution: distribution,
        typeDistribution: [],
        analysisTimeRange: '近30天',
        onTimeRangeChanged: (_) {},
        onDateRangeChanged: (_, __) {},
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text('暂无数据'), findsOneWidget); // 仅环形图区域
    });

    testWidgets('时间范围 dropdown 点击触发 onTimeRangeChanged', (tester) async {
      // Arrange
      String? selected;
      final card = DualAnalysisCard(
        distribution: [],
        typeDistribution: [],
        analysisTimeRange: '近30天',
        onTimeRangeChanged: (v) => selected = v,
        onDateRangeChanged: (_, __) {},
      );

      // Act
      await pumpTestWidget(tester, card);
      // 点击 dropdown
      await tester.tap(find.text('近30天'));
      await tester.pump();
      // 选择另一个选项
      final item = find.text('近7天').last;
      await tester.tap(item);
      await tester.pump();

      // Assert
      expect(selected, '近7天');
    });
  });
}
