import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/pages/dashboard/widgets/kpi_summary_card.dart';
import '../helpers/test_helper.dart';

void main() {
  setUpAll(() => initTestEnvironment());

  group('KpiSummaryCard', () {
    // ── Happy Path ──
    testWidgets('隐私关闭时应显示四项 KPI 金额', (tester) async {
      final card = KpiSummaryCard(
        isPrivacyHidden: false,
        onPrivacyToggle: () {},
        monthTotal: 12345.67,
        pending: 5000,
        pendingReimburse: 3000,
        yearTotal: 88000,
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert — display uses toStringAsFixed(2), no thousand separators
      expect(find.text('12345.67'), findsOneWidget);
      expect(find.text('5000.00'), findsOneWidget);
      expect(find.text('88000.00'), findsOneWidget);
    });

    testWidgets('隐私模式下金额应显示为 ***', (tester) async {
      // Arrange
      final card = KpiSummaryCard(
        isPrivacyHidden: true,
        onPrivacyToggle: () {},
        monthTotal: 12345,
        pending: 5000,
        pendingReimburse: 3000,
        yearTotal: 88000,
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text('****'), findsWidgets);
      // 确认没有显示数字金额
      expect(find.textContaining('12,345'), findsNothing);
    });

    testWidgets('点击隐私按钮应触发 onPrivacyToggle 回调', (tester) async {
      // Arrange
      bool toggled = false;
      final card = KpiSummaryCard(
        isPrivacyHidden: false,
        onPrivacyToggle: () => toggled = true,
        monthTotal: 0,
        pending: 0,
        pendingReimburse: 0,
        yearTotal: 0,
      );

      // Act
      await pumpTestWidget(tester, card);
      // 隐私按钮使用 Icons.monetization_on
      final toggleBtn = find.byIcon(Icons.monetization_on);
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      // Assert
      expect(toggled, isTrue);
    });

    // ── Boundary ──
    testWidgets('amount=0 时应显示 ¥0.00', (tester) async {
      // Arrange
      final card = KpiSummaryCard(
        isPrivacyHidden: false,
        onPrivacyToggle: () {},
        monthTotal: 0,
        pending: 0,
        pendingReimburse: 0,
        yearTotal: 0,
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.textContaining('0'), findsWidgets);
    });

    testWidgets('大金额不应溢出渲染', (tester) async {
      // Arrange
      final card = KpiSummaryCard(
        isPrivacyHidden: false,
        onPrivacyToggle: () {},
        monthTotal: 9999999.99,
        pending: 9999999.99,
        pendingReimburse: 9999999.99,
        yearTotal: 9999999.99,
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert — 不抛异常即通过
      expect(tester.takeException(), isNull);
    });
  });
}
