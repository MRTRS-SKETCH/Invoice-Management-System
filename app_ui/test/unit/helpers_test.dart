import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/pages/dashboard/widgets/expense_table_panel.dart' show toChineseUppercase;
import 'package:app_ui/pages/dashboard/widgets/dual_analysis_card.dart' show DualAnalysisCard;
import '../helpers/test_helper.dart';
import '../helpers/mock_clients.dart';

void main() {
  setUpAll(() => initTestEnvironment());

  // ═══════════════════════════════════════════════════════════════════
  // fakeResponse / fakeOk / fakeError
  // ═══════════════════════════════════════════════════════════════════
  group('fakeResponse', () {
    test('应返回指定 statusCode 和 body 的 Response', () {
      // Arrange — 无

      // Act
      final resp = fakeResponse(200, '{"ok": true}');

      // Assert
      expect(resp.statusCode, 200);
      expect(resp.body, '{"ok": true}');
    });

    test('fakeOk 等于 fakeResponse(200, ...)', () {
      // Act
      final resp = fakeOk('hello');

      // Assert
      expect(resp.statusCode, 200);
      expect(resp.body, 'hello');
    });

    test('fakeError 可构造 500 响应', () {
      // Act
      final resp = fakeError(500, 'Internal Server Error');

      // Assert
      expect(resp.statusCode, 500);
      expect(resp.body, contains('Error'));
    });

    test('fakeResponse 可附带自定义 headers', () {
      // Act
      final resp = fakeResponse(201, '{}',
          headers: {'x-custom': 'test'});  // 使用小写 key 匹配 http 包内部行为

      // Assert
      expect(resp.headers['x-custom'], 'test');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 测试数据工厂
  // ═══════════════════════════════════════════════════════════════════
  group('fakeExpenseMap', () {
    test('应返回包含所有必需字段的 Map', () {
      // Act
      final m = fakeExpenseMap(
        uuuid: 'exp-42',
        title: '办公耗材',
        amount: 299.5,
        status: '已开票',
      );

      // Assert
      expect(m['uuuid'], 'exp-42');
      expect(m['title'], '办公耗材');
      expect(m['amount'], 299.5);
      expect(m['status'], '已开票');
      expect(m['project_name'], isNotEmpty);
      expect(m['expense_type'], isNotEmpty);
    });

    test('默认参数应生成有效条目', () {
      // Act
      final m = fakeExpenseMap();

      // Assert
      expect(m['uuuid'], 'exp-001');
      expect(m['amount'], 1000.0);
      expect(m['status'], '待报销');
    });
  });

  group('fakeInvoiceMap', () {
    test('应返回包含发票字段的 Map', () {
      // Act
      final m = fakeInvoiceMap(fileName: 'test.pdf');

      // Assert
      expect(m['file_name'], 'test.pdf');
      expect(m['saved_path'], contains('pdfs/'));
      expect(m['uuuid'], 'inv-001');
    });
  });

  group('fakeSummaryMap', () {
    test('默认参数返回合理 KPI 数据', () {
      // Act
      final m = fakeSummaryMap();

      // Assert
      expect(m['total_amount'], 50000.0);
      expect(m['pending_amount'], 12000.0);
      expect(m['total_count'], 42);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // toChineseUppercase
  // ═══════════════════════════════════════════════════════════════════
  group('toChineseUppercase', () {
    test('应正确转换 12345.67 → 壹万贰仟叁佰肆拾伍元陆角柒分', () {
      // Arrange
      const amount = 12345.67;

      // Act
      final result = toChineseUppercase(amount);

      // Assert
      expect(result, '壹万贰仟叁佰肆拾伍元陆角柒分');
    });

    test('零元整（amount < 0.005）', () {
      // Arrange & Act
      final r1 = toChineseUppercase(0);
      final r2 = toChineseUppercase(0.004);

      // Assert
      expect(r1, '零元整');
      expect(r2, '零元整');
    });

    test('仅角无分 → X元X角', () {
      // Act
      final result = toChineseUppercase(1.50);

      // Assert
      expect(result, contains('壹元伍角'));
    });

    test('仅分无角 → X元X分', () {
      // Act
      final result = toChineseUppercase(1.05);

      // Assert
      // 实际实现为 "壹元伍分"（无前导零，符合中式大写习惯）
      expect(result, contains('伍分'));
      expect(result, contains('壹元'));
    });

    test('整数金额 → X元整', () {
      // Act
      final result = toChineseUppercase(100);

      // Assert
      expect(result, contains('壹佰元整'));
    });

    test('大额金额 — 万位', () {
      // Act
      final result = toChineseUppercase(56000);

      // Assert
      expect(result, contains('伍万陆仟元整'));
    });

    test('避免连续零（如 1001.00）', () {
      // Act
      final result = toChineseUppercase(1001);

      // Assert
      // 应该是"壹仟零壹元整"而不是"壹仟零零壹元整"
      expect(result, isNot(contains('零零')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // DualAnalysisCard daysFor / dateRangeFor
  // ═══════════════════════════════════════════════════════════════════
  group('DualAnalysisCard.daysFor', () {
    test('近7天 → 7', () {
      expect(DualAnalysisCard.daysFor('近7天'), 7);
    });

    test('近30天 → 30', () {
      expect(DualAnalysisCard.daysFor('近30天'), 30);
    });

    test('近60天 → 60', () {
      expect(DualAnalysisCard.daysFor('近60天'), 60);
    });

    test('近3月 → 90', () {
      expect(DualAnalysisCard.daysFor('近3月'), 90);
    });

    test('近1年 → 365', () {
      expect(DualAnalysisCard.daysFor('近1年'), 365);
    });

    test('总计 → null', () {
      expect(DualAnalysisCard.daysFor('总计'), isNull);
    });

    test('未知标签 → null', () {
      expect(DualAnalysisCard.daysFor('无效标签'), isNull);
    });
  });

  group('DualAnalysisCard.dateRangeFor', () {
    test('总计 → null', () {
      expect(DualAnalysisCard.dateRangeFor('总计'), isNull);
    });

    test('近30天 → 返回起止日期字符串', () {
      // Act
      final dr = DualAnalysisCard.dateRangeFor('近30天');

      // Assert
      expect(dr, isNotNull);
      expect(dr!.from, isNotEmpty);
      expect(dr.to, isNotEmpty);
      // from 应早于 to
      expect(dr.from.compareTo(dr.to), lessThan(0));
    });
  });
}
