import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:app_ui/services/expense_service.dart';
import 'package:app_ui/widgets/settings_dialog.dart';
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

  /// 辅助：pump 直到异步数据加载完成（避免 CircularProgressIndicator 导致 pumpAndSettle 超时）
  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      // 检查 loading 是否完成（"路径设置" 标题一直在，但"数据库路径"标签在加载后出现）
      if (find.text('数据库路径').evaluate().isNotEmpty) break;
    }
  }

  group('SettingsDialog', () {
    testWidgets('加载时应显示路径标签', (tester) async {
      // Arrange
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => fakeOk('{"db_path":"/data/db","log_path":"/data/log"}'),
      );
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk(
              '{"db_structure":[],"log_structure":[],"pdf_path":"/data/db/pdfs/"}'));

      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SettingsDialog(),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await pumpUntilLoaded(tester);

      // Assert
      expect(find.text('路径设置'), findsOneWidget);
      expect(find.text('数据库路径'), findsOneWidget);
      expect(find.text('日志路径'), findsOneWidget);
      expect(find.text('PDF 路径'), findsOneWidget);
    });

    testWidgets('加载失败应不崩溃', (tester) async {
      // Arrange
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeError(500, '{}'));

      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SettingsDialog(),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      // _loadCurrentConfig 会 catch 错误并 setState
      await pumpUntilLoaded(tester);

      // Assert — 对话框仍然存在
      expect(find.byType(SettingsDialog), findsOneWidget);
    });

    testWidgets('显示取消和保存和重新连接按钮', (tester) async {
      // Arrange
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => fakeOk('{"db_path":"/db","log_path":"/log"}'),
      );
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk(
              '{"db_structure":[],"log_structure":[],"pdf_path":"/db/pdfs/"}'));

      await pumpTestWidget(
        tester,
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SettingsDialog(),
            ),
            child: const Text('Open'),
          );
        }),
      );

      // Act
      await tester.tap(find.text('Open'));
      await pumpUntilLoaded(tester);

      // Assert
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('重新连接'), findsOneWidget);
    });
  });
}
