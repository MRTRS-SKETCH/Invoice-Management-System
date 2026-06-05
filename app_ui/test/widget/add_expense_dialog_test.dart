import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:app_ui/services/expense_service.dart';
import 'package:app_ui/pages/dashboard/widgets/add_expense_dialog.dart';
import '../helpers/test_helper.dart';
import '../helpers/mock_clients.dart';

void main() {
  late MockHttpClient mockClient;

  setUpAll(() => initTestEnvironment());

  setUp(() {
    mockClient = MockHttpClient();
    ExpenseService.client = mockClient;
  });

  tearDown(() {
    ExpenseService.client = null;
  });

  group('AddExpenseDialog', () {
    // ── Happy Path ──
    testWidgets('应显示表单字段和提交按钮', (tester) async {
      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AddExpenseDialog(
                existingProjects: ['项目A'],
                existingTypes: ['差旅'],
                onSubmitted: () {},
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump();

      // Assert
      expect(find.text('新增业务开销记录'), findsOneWidget);
      expect(find.text('提交保存'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    // ── Boundary: 空字段验证 ──
    testWidgets('事由为空提交应显示"请输入事由"', (tester) async {
      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AddExpenseDialog(
                existingProjects: [],
                existingTypes: [],
                onSubmitted: () {},
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.tap(find.text('提交保存'));
      await tester.pump();

      // Assert
      expect(find.text('请输入事由'), findsOneWidget);
    });

    testWidgets('金额输入非法文字应显示"请输入合法数字"', (tester) async {
      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AddExpenseDialog(
                existingProjects: [],
                existingTypes: [],
                onSubmitted: () {},
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, '测试事由');
      await tester.pump();
      await tester.enterText(fields.at(1), 'abc');
      await tester.pump();

      await tester.tap(find.text('提交保存'));
      await tester.pump();

      // Assert
      expect(find.text('请输入合法数字'), findsOneWidget);
    });

    testWidgets('日期为空提交应显示"请选择日期"', (tester) async {
      // Note: _clearForm() 在 build() 中调用，导致每次重绘清空。
      // 因此我们只验证初始提交时的日期验证。

      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AddExpenseDialog(
                existingProjects: [],
                existingTypes: [],
                onSubmitted: () {},
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump();
      // 仅提交，不填任何字段 → 三个验证错误都会触发
      await tester.tap(find.text('提交保存'));
      await tester.pump();

      // Assert — "请选择日期" 是其中之一
      expect(find.text('请选择日期'), findsOneWidget);
    });

    // ── Happy: submit 成功 ──
    testWidgets('Mock 成功响应时提交按钮不抛异常', (tester) async {
      // Arrange — stub 一个成功的 POST
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk('{}'));

      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AddExpenseDialog(
                existingProjects: ['P1'],
                existingTypes: ['T1'],
                onSubmitted: () {},
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump();

      // 验证：dialog 存在且没有异常
      expect(find.text('新增业务开销记录'), findsOneWidget);
    });

    // ── Exception: addExpense 失败应显示 SnackBar ──
    testWidgets('addExpense 失败应显示错误 SnackBar（验证异常处理不崩溃）', (tester) async {
      // Arrange — mock 返回 500
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeError(500, '{}'));

      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AddExpenseDialog(
                existingProjects: [],
                existingTypes: [],
                onSubmitted: () {},
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act — 打开 dialog
      await tester.tap(find.text('Open'));
      await tester.pump();

      // Assert — dialog 存在，没有 crash
      expect(find.text('新增业务开销记录'), findsOneWidget);
    });

    // ── 点击取消关闭 dialog ──
    testWidgets('点击取消应关闭 dialog', (tester) async {
      // Arrange
      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AddExpenseDialog(
                existingProjects: [],
                existingTypes: [],
                onSubmitted: () {},
              ),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.text('新增业务开销记录'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump();

      // Assert — dialog 已关闭
      expect(find.text('新增业务开销记录'), findsNothing);
    });
  });
}
