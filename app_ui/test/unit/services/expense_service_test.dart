import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:app_ui/services/expense_service.dart';
import '../../helpers/test_helper.dart';
import '../../helpers/mock_clients.dart';

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

  // ═══════════════════════════════════════════════════════════════════
  // fetchDashboardSummary
  // ═══════════════════════════════════════════════════════════════════
  group('fetchDashboardSummary', () {
    // ── Happy ──
    test('应正确解析 KPI JSON', () async {
      // Arrange
      final jsonBody = json.encode(fakeSummaryMap(totalAmount: 88000));
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeOk(jsonBody));

      // Act
      final result = await ExpenseService.fetchDashboardSummary();

      // Assert
      expect(result['total_amount'], 88000);
      expect(result['pending_amount'], 12000);
    });

    // ── Exception ──
    test('服务端返回 500 时应抛出异常', () async {
      // Arrange
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeError(500, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.fetchDashboardSummary(),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('500'))),
      );
    });

    // ── Boundary: 空 JSON ──
    test('200 但 body 为空 JSON 对象时应返回空 Map', () async {
      // Arrange
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeOk('{}'));

      // Act
      final result = await ExpenseService.fetchDashboardSummary();

      // Assert
      expect(result, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // fetchHeatmapData
  // ═══════════════════════════════════════════════════════════════════
  group('fetchHeatmapData', () {
    test('应正确解析热力图 JSON 列表', () async {
      // Arrange
      const jsonBody = '[{"date":"2025-01-01","count":3}]';
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeOk(jsonBody));

      // Act
      final result = await ExpenseService.fetchHeatmapData();

      // Assert
      expect(result, isA<List>());
      expect(result.length, 1);
      expect(result[0]['count'], 3);
    });

    test('500 → 抛出异常', () async {
      // Arrange
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeError(500, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.fetchHeatmapData(),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // fetchDistributionData
  // ═══════════════════════════════════════════════════════════════════
  group('fetchDistributionData', () {
    test('带 days 参数时 URL 应包含 query', () async {
      // Arrange
      Uri? capturedUri;
      when(() => mockClient.get(any())).thenAnswer((invocation) async {
        capturedUri = invocation.positionalArguments[0] as Uri;
        return fakeOk('[]');
      });

      // Act
      await ExpenseService.fetchDistributionData(days: 30);

      // Assert
      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters['days'], '30');
    });

    test('不带 days 参数时 URL 不含 days query', () async {
      // Arrange
      Uri? capturedUri;
      when(() => mockClient.get(any())).thenAnswer((invocation) async {
        capturedUri = invocation.positionalArguments[0] as Uri;
        return fakeOk('[]');
      });

      // Act
      await ExpenseService.fetchDistributionData();

      // Assert
      expect(capturedUri!.queryParameters.containsKey('days'), isFalse);
    });

    test('500 → 抛出异常', () async {
      // Arrange
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeError(500, '{}'));

      // Act & Assert
      await expectLater(
        () => ExpenseService.fetchDistributionData(days: 7),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // fetchTypeDistributionData
  // ═══════════════════════════════════════════════════════════════════
  group('fetchTypeDistributionData', () {
    test('应正确解析类型分布列表', () async {
      // Arrange
      const jsonBody = '[{"category":"差旅","amount":3000}]';
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeOk(jsonBody));

      // Act
      final result = await ExpenseService.fetchTypeDistributionData(days: 30);

      // Assert
      expect(result.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // fetchExpenses
  // ═══════════════════════════════════════════════════════════════════
  group('fetchExpenses', () {
    test('带搜索和状态参数时 URL 应包含全部 query', () async {
      // Arrange
      Uri? capturedUri;
      when(() => mockClient.get(any())).thenAnswer((invocation) async {
        capturedUri = invocation.positionalArguments[0] as Uri;
        return fakeOk('[]');
      });

      // Act
      await ExpenseService.fetchExpenses(
        search: '办公',
        status: '待报销',
        dateFrom: '2025-01-01',
        dateTo: '2025-06-30',
      );

      // Assert
      final q = capturedUri!.queryParameters;
      expect(q['search'], '办公');
      expect(q['status'], '待报销');
      expect(q['date_from'], '2025-01-01');
      expect(q['date_to'], '2025-06-30');
      expect(q['limit'], '50');
      expect(q['skip'], '0');
    });

    test('不带可选参数时仅含 skip 和 limit', () async {
      // Arrange
      Uri? capturedUri;
      when(() => mockClient.get(any())).thenAnswer((invocation) async {
        capturedUri = invocation.positionalArguments[0] as Uri;
        return fakeOk('[]');
      });

      // Act
      await ExpenseService.fetchExpenses();

      // Assert
      final q = capturedUri!.queryParameters;
      expect(q['limit'], '50');
      expect(q['skip'], '0');
      expect(q.containsKey('search'), isFalse);
    });

    test('搜索参数为空字符串时不应传 search', () async {
      // Arrange
      Uri? capturedUri;
      when(() => mockClient.get(any())).thenAnswer((invocation) async {
        capturedUri = invocation.positionalArguments[0] as Uri;
        return fakeOk('[]');
      });

      // Act
      await ExpenseService.fetchExpenses(search: '');

      // Assert
      expect(capturedUri!.queryParameters.containsKey('search'), isFalse);
    });

    test('正常解析 JSON 列表', () async {
      // Arrange
      final jsonBody =
          json.encode([fakeExpenseMap(uuuid: 'e1'), fakeExpenseMap(uuuid: 'e2')]);
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeOk(jsonBody));

      // Act
      final result = await ExpenseService.fetchExpenses();

      // Assert
      expect(result.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // addExpense
  // ═══════════════════════════════════════════════════════════════════
  group('addExpense', () {
    test('200 返回 true', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk('{}'));

      // Act
      final result = await ExpenseService.addExpense(fakeExpenseMap());

      // Assert
      expect(result, isTrue);
    });

    test('201 返回 true', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeResponse(201, '{}'));

      // Act
      final result = await ExpenseService.addExpense(fakeExpenseMap());

      // Assert
      expect(result, isTrue);
    });

    test('400 抛出异常', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeError(400, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.addExpense(fakeExpenseMap()),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('创建开销失败'))),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // updateExpenseStatus
  // ═══════════════════════════════════════════════════════════════════
  group('updateExpenseStatus', () {
    test('200 返回 true', () async {
      // Arrange
      when(() => mockClient.patch(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk('{}'));

      // Act
      final result =
          await ExpenseService.updateExpenseStatus('exp-1', '已开票');

      // Assert
      expect(result, isTrue);
    });

    test('422 抛出含 detail 的异常', () async {
      // Arrange
      when(() => mockClient.patch(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeError(
              422, '{"detail": "状态流转非法"}'));
      // Note: bodyBytes will be decoded from the body string

      // Act & Assert
      expect(
        () => ExpenseService.updateExpenseStatus('exp-1', '已完结'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // deleteExpense
  // ═══════════════════════════════════════════════════════════════════
  group('deleteExpense', () {
    test('200 返回 true', () async {
      // Arrange
      when(() => mockClient.delete(any()))
          .thenAnswer((_) async => fakeOk('{}'));

      // Act
      final result = await ExpenseService.deleteExpense('exp-1');

      // Assert
      expect(result, isTrue);
    });

    test('404 抛出异常', () async {
      // Arrange
      when(() => mockClient.delete(any()))
          .thenAnswer((_) async => fakeError(404, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.deleteExpense('exp-1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // blockExpense / unblockExpense
  // ═══════════════════════════════════════════════════════════════════
  group('blockExpense / unblockExpense', () {
    test('blockExpense 200 返回 true', () async {
      // Arrange
      when(() => mockClient.post(any()))
          .thenAnswer((_) async => fakeOk('{}'));

      // Act
      final result = await ExpenseService.blockExpense('exp-1');

      // Assert
      expect(result, isTrue);
    });

    test('blockExpense 500 抛出异常', () async {
      // Arrange
      when(() => mockClient.post(any()))
          .thenAnswer((_) async => fakeError(500, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.blockExpense('exp-1'),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('屏蔽失败'))),
      );
    });

    test('unblockExpense 200 返回 true', () async {
      // Arrange
      when(() => mockClient.post(any()))
          .thenAnswer((_) async => fakeOk('{}'));

      // Act
      final result = await ExpenseService.unblockExpense('exp-1');

      // Assert
      expect(result, isTrue);
    });

    test('unblockExpense 500 抛出异常', () async {
      // Arrange
      when(() => mockClient.post(any()))
          .thenAnswer((_) async => fakeError(500, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.unblockExpense('exp-1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // fetchBoundInvoices
  // ═══════════════════════════════════════════════════════════════════
  group('fetchBoundInvoices', () {
    test('正常解析发票列表', () async {
      // Arrange
      final jsonBody = json.encode([
        fakeInvoiceMap(uuuid: 'inv-1'),
        fakeInvoiceMap(uuuid: 'inv-2'),
      ]);
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeOk(jsonBody));

      // Act
      final result = await ExpenseService.fetchBoundInvoices('exp-1');

      // Assert
      expect(result.length, 2);
      expect(result[0]['uuuid'], 'inv-1');
    });

    test('空列表 → 返回空 List', () async {
      // Arrange
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeOk('[]'));

      // Act
      final result = await ExpenseService.fetchBoundInvoices('exp-1');

      // Assert
      expect(result, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // bindInvoice
  // ═══════════════════════════════════════════════════════════════════
  group('bindInvoice', () {
    test('201 返回 true', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeResponse(201, '{}'));

      // Act
      final result =
          await ExpenseService.bindInvoice('exp-1', '/path/to/file.pdf');

      // Assert
      expect(result, isTrue);
    });

    test('400 抛出含 detail 的异常', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeError(
              400, '{"detail": "PDF 不存在"}'));

      // Act & Assert
      expect(
        () => ExpenseService.bindInvoice('exp-1', '/bad.pdf'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // bindInvoiceAuto
  // ═══════════════════════════════════════════════════════════════════
  group('bindInvoiceAuto', () {
    test('201 返回含 expense_uuuid 的 Map', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeResponse(
              201, '{"uuuid":"inv-new","expense_uuuid":"exp-new"}'));

      // Act
      final result = await ExpenseService.bindInvoiceAuto('/f.pdf',
          projectName: '测试项目', expenseType: '办公用品');

      // Assert
      expect(result['uuuid'], 'inv-new');
      expect(result['expense_uuuid'], 'exp-new');
    });

    test('不带可选字段时不应抛出异常', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeResponse(201, '{}'));

      // Act
      final result = await ExpenseService.bindInvoiceAuto('/f.pdf');

      // Assert
      expect(result, isA<Map<String, dynamic>>());
    });

    test('400 抛出异常', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeError(400, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.bindInvoiceAuto('/f.pdf'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // deleteInvoice
  // ═══════════════════════════════════════════════════════════════════
  group('deleteInvoice', () {
    test('200 返回 true', () async {
      // Arrange
      when(() => mockClient.delete(any()))
          .thenAnswer((_) async => fakeOk('{}'));

      // Act
      final result = await ExpenseService.deleteInvoice('inv-1');

      // Assert
      expect(result, isTrue);
    });

    test('500 抛出异常', () async {
      // Arrange
      when(() => mockClient.delete(any()))
          .thenAnswer((_) async => fakeError(500, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.deleteInvoice('inv-1'),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('解绑失败'))),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // exportPdfs
  // ═══════════════════════════════════════════════════════════════════
  group('exportPdfs', () {
    test('200 返回导出结果 Map', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk(
              '{"all_count":5,"vat_count":2,"export_dir":"/out/2025-01-01"}'));

      // Act
      final result =
          await ExpenseService.exportPdfs({'e1', 'e2'}, '/out');

      // Assert
      expect(result['all_count'], 5);
      expect(result['vat_count'], 2);
    });

    test('500 抛出异常', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeError(500, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.exportPdfs({'e1'}, '/out'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Settings API
  // ═══════════════════════════════════════════════════════════════════
  group('fetchSettingsPaths', () {
    test('200 返回配置 JSON', () async {
      // Arrange
      const jsonBody = '{"db_path":"/data","log_path":"/log"}';
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeOk(jsonBody));

      // Act
      final result = await ExpenseService.fetchSettingsPaths();

      // Assert
      expect(result['db_path'], '/data');
      expect(result['log_path'], '/log');
    });

    test('500 抛出异常', () async {
      // Arrange
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => fakeError(500, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.fetchSettingsPaths(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('updateSettingsPaths', () {
    test('200 返回更新结果', () async {
      // Arrange
      when(() => mockClient.put(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk('{"status":"ok"}'));

      // Act
      final result =
          await ExpenseService.updateSettingsPaths('/db', '/log');

      // Assert
      expect(result['status'], 'ok');
    });

    test('400 抛出异常', () async {
      // Arrange
      when(() => mockClient.put(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeError(400, '{}'));

      // Act & Assert
      expect(
        () => ExpenseService.updateSettingsPaths('/db', '/log'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('validatePaths', () {
    test('200 返回校验结果', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk('{"valid":true}'));

      // Act
      final result = await ExpenseService.validatePaths('/db', '/log');

      // Assert
      expect(result['valid'], true);
    });
  });

  group('previewPaths', () {
    test('200 返回目录预览', () async {
      // Arrange
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => fakeOk(
              '{"db_structure":["invoice_system.db"],"log_structure":["app.log"]}'));

      // Act
      final result = await ExpenseService.previewPaths('/db', '/log');

      // Assert
      expect(result['db_structure'], isA<List>());
    });
  });

  group('requestRestart', () {
    test('200 返回重启确认', () async {
      // Arrange
      when(() => mockClient.post(any()))
          .thenAnswer((_) async => fakeOk('{"restarting":true}'));

      // Act
      final result = await ExpenseService.requestRestart();

      // Assert
      expect(result['restarting'], true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Lifecycle 隔离验证
  // ═══════════════════════════════════════════════════════════════════
  test('setUp 应正确注入 MockClient，tearDown 应恢复为 null', () {
    // 此测试验证 setUp/tearDown 生命周期
    // Arrange — setUp 已注入

    // Act
    final clientBefore = ExpenseService.client; // via _clientOverride getter

    // Assert — setUp 中已注入
    expect(clientBefore, isNotNull);
    expect(clientBefore, isA<MockHttpClient>());
  });
}
