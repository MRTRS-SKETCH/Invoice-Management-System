import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/pages/dashboard/widgets/batch_upload_dialog.dart';
import '../helpers/test_helper.dart';

void main() {
  setUpAll(() => initTestEnvironment());

  // Note: BatchUploadDialog 使用 PopScope(canPop: false)，该组件在
  // showDialog 上下文中才能正常工作。以下 Widget 测试通过直接 pump 验证渲染。

  group('BatchUploadDialog', () {
    testWidgets('total=5 时应显示进度提示文字', (tester) async {
      // Arrange — 通过 showDialog 包裹以提供 ModalRoute 上下文
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const BatchUploadDialog(total: 5),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump(); // CircularProgressIndicator 持续动画 → 不用 pumpAndSettle

      // Assert
      expect(find.text('正在智能解析发票...'), findsOneWidget);
      expect(find.textContaining('共 5 张'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('total=1 时应显示"共 1 张"（单数）', (tester) async {
      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const BatchUploadDialog(total: 1),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump(); // CircularProgressIndicator 持续动画

      // Assert
      expect(find.textContaining('共 1 张'), findsOneWidget);
    });

    testWidgets('total=0 不应崩溃', (tester) async {
      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const BatchUploadDialog(total: 0),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump(); // CircularProgressIndicator 持续动画

      // Assert
      expect(find.textContaining('共 0 张'), findsOneWidget);
    });
  });

  group('BatchInfoDialog', () {
    testWidgets('应显示配置表单和两个按钮', (tester) async {
      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const BatchInfoDialog(
                existingProjects: ['项目A'],
                existingTypes: ['差旅交通'],
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('批量建档配置'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
      expect(find.text('开始导入'), findsOneWidget);
    });

    testWidgets('点击跳过按钮应关闭 Dialog（返回 null）', (tester) async {
      // Arrange
      Map<String, String>? result = {'sentinel': 'not-popped'};
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await showDialog<Map<String, String>>(
                context: context,
                builder: (_) => const BatchInfoDialog(
                  existingProjects: [],
                  existingTypes: [],
                ),
              );
            },
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();

      // Assert
      expect(result, isNull);
    });

    testWidgets('点击开始导入应返回 Map', (tester) async {
      // Arrange
      Map<String, String>? result;
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await showDialog<Map<String, String>>(
                context: context,
                builder: (_) => const BatchInfoDialog(
                  existingProjects: ['P1'],
                  existingTypes: ['T1'],
                ),
              );
            },
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始导入'));
      await tester.pumpAndSettle();

      // Assert
      expect(result, isNotNull);
      expect(result!.containsKey('project_name'), isTrue);
      expect(result!.containsKey('expense_type'), isTrue);
    });

    testWidgets('空 options 时不应崩溃', (tester) async {
      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const BatchInfoDialog(
                existingProjects: [],
                existingTypes: [],
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('批量建档配置'), findsOneWidget);
    });
  });
}
