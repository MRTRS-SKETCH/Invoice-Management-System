import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/widgets/glass_card.dart';
import '../helpers/test_helper.dart';

void main() {
  setUpAll(() => initTestEnvironment());

  group('GlassCard', () {
    // ── Happy Path ──
    testWidgets('应正确渲染子组件', (tester) async {
      // Arrange
      const childText = 'Hello Glass';
      const card = GlassCard(child: Text(childText));

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text(childText), findsOneWidget);
    });

    testWidgets('自定义 padding 不应报错', (tester) async {
      // Arrange
      const card = GlassCard(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text('Test'),
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('自定义 borderRadius 不应报错', (tester) async {
      // Arrange
      const card = GlassCard(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        child: Text('Round'),
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text('Round'), findsOneWidget);
    });

    // ── Boundary ──
    testWidgets('子组件为 SizedBox.shrink 不报错', (tester) async {
      // Arrange
      final card = GlassCard(child: const SizedBox.shrink());

      // Act
      await pumpTestWidget(tester, card);

      // Assert — 不抛异常即通过
      expect(tester.takeException(), isNull);
    });

    testWidgets('子组件为 Column 多子元素正常渲染', (tester) async {
      // Arrange
      final card = GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('A'),
            Text('B'),
          ],
        ),
      );

      // Act
      await pumpTestWidget(tester, card);

      // Assert
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });
}
