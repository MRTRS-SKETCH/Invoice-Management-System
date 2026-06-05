import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:app_ui/services/expense_service.dart';
import 'package:app_ui/pages/dashboard/unified_dashboard_page.dart';
import 'package:app_ui/main.dart' show forceBackendReady;
import '../helpers/test_helper.dart';
import '../helpers/mock_clients.dart';

/// 集成测试：UnifiedDashboardPage
///
/// 使用 Mock ExpenseService 模拟后端，验证页面加载流程。
void main() {
  late MockHttpClient mockClient;

  setUpAll(() => initTestEnvironment());

  setUp(() {
    mockClient = MockHttpClient();
    ExpenseService.client = mockClient;
    forceBackendReady();
  });

  tearDown(() {
    ExpenseService.client = null;
  });

  void stubAllApiSuccess() {
    when(() => mockClient.get(any())).thenAnswer((invocation) {
      final uri = invocation.positionalArguments[0] as Uri;
      final path = uri.path;
      String body;
      if (path.endsWith('/dashboard/summary')) {
        body = '{"total_amount":88000,"pending_amount":12000,"total_count":42,"pending_count":15}';
      } else if (path.endsWith('/dashboard/heatmap')) {
        body = '[{"date":"2025-01-01","count":3}]';
      } else if (path.endsWith('/dashboard/distribution')) {
        body = '[{"category":"项目A","amount":5000}]';
      } else if (path.endsWith('/dashboard/type-distribution')) {
        body = '[{"category":"差旅","percentage":0.6}]';
      } else {
        body = '[]';
      }
      return Future.value(fakeOk(body));
    });

    when(() => mockClient.post(any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'))).thenAnswer((_) async => fakeOk('{}'));
    when(() => mockClient.patch(any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'))).thenAnswer((_) async => fakeOk('{}'));
    when(() => mockClient.put(any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'))).thenAnswer((_) async => fakeOk('{}'));
    when(() => mockClient.delete(any())).thenAnswer((_) async => fakeOk('{}'));
  }

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const Scaffold(body: SafeArea(child: UnifiedDashboardPage())),
      ),
    );
    tester.view.physicalSize =
        const Size(1400, 900) * tester.view.devicePixelRatio;
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  testWidgets('API 成功 — 页面渲染不崩溃', (tester) async {
    // Arrange
    stubAllApiSuccess();

    // Act
    await pumpDashboard(tester);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Assert
    expect(tester.takeException(), isNull);
  });

  testWidgets('API 全部失败 — 页面不崩溃', (tester) async {
    // Arrange — 所有 API 返回 500
    when(() => mockClient.get(any()))
        .thenAnswer((_) async => fakeError(500, '{}'));
    when(() => mockClient.post(any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'))).thenAnswer((_) async => fakeError(500, '{}'));
    when(() => mockClient.patch(any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'))).thenAnswer((_) async => fakeError(500, '{}'));
    when(() => mockClient.put(any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'))).thenAnswer((_) async => fakeError(500, '{}'));
    when(() => mockClient.delete(any()))
        .thenAnswer((_) async => fakeError(500, '{}'));

    // Act
    await pumpDashboard(tester);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Assert
    expect(tester.takeException(), isNull);
  });
}
