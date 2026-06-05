import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:app_ui/services/expense_service.dart';
import 'mock_clients.dart';

// ═══════════════════════════════════════════════════════════════════
// 全局 setUpAll / tearDown
// ═══════════════════════════════════════════════════════════════════

/// 在所有测试套件启动前调用一次：注册 mocktail fallback + 重置 Mock。
/// 建议在顶层 `setUpAll` 中调用。
void initTestEnvironment() {
  initMocktailFallbacks();
}

/// 每个测试用例结束后调用的标准清算逻辑。
/// 放在 `tearDown` 中调用。
void resetTestEnvironment() {
  resetMocktailState();
  ExpenseService.client = null; // 还原默认 HTTP 客户端
}

/// 重置所有 `mocktail` Mock 对象的调用记录（对每次测试独立隔离）。
void resetMocktailState() {
  reset(MockHttpClient());
  reset(MockSharedPreferences());
}

// ═══════════════════════════════════════════════════════════════════
// Widget 测试通用 Wrapper
// ═══════════════════════════════════════════════════════════════════

/// 为单个 Widget 提供一致的 Material 上下文：主题 + Scaffold + 安全区域。
///
/// 用法：
/// ```dart
/// await pumpTestWidget(
///   tester, 
///   KpiSummaryCard(monthTotal: 1000, ...),
/// );
/// ```
Future<void> pumpTestWidget(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  Size surfaceSize = const Size(1024, 768),
}) async {
  await tester.pumpWidget(
    _TestWrapper(
      theme: theme,
      child: child,
    ),
  );
  // 设置逻辑尺寸（模拟桌面窗口），让 FittedBox / Expanded 有可用空间
  tester.view.physicalSize = surfaceSize * tester.view.devicePixelRatio;
  addTearDown(() => tester.view.resetPhysicalSize());
  await tester.pumpAndSettle();
}

/// 内部包装组件：注入 MaterialApp + Scaffold（含 SafeArea）。
class _TestWrapper extends StatelessWidget {
  final Widget child;
  final ThemeData? theme;
  const _TestWrapper({required this.child, this.theme});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: theme ?? ThemeData.light(),
      home: Scaffold(body: SafeArea(child: child)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 通用测试数据工厂
// ═══════════════════════════════════════════════════════════════════

/// 构造一条标准开销记录的 Map（模拟后端 JSON 返回）。
Map<String, dynamic> fakeExpenseMap({
  String uuuid = 'exp-001',
  String title = '测试开销',
  double amount = 1000.0,
  String status = '待报销',
  String projectName = '默认项目',
  String expenseType = '办公用品',
  String incurredDate = '2025-01-15',
  String? note,
}) {
  return {
    'uuuid': uuuid,
    'title': title,
    'amount': amount,
    'status': status,
    'project_name': projectName,
    'expense_type': expenseType,
    'incurred_date': incurredDate,
    'note': note ?? '',
  };
}

/// 构造一条标准发票记录的 Map。
Map<String, dynamic> fakeInvoiceMap({
  String uuuid = 'inv-001',
  String expenseUuuid = 'exp-001',
  String fileName = '发票001.pdf',
  String savedPath = 'pdfs/发票001.pdf',
}) {
  return {
    'uuuid': uuuid,
    'expense_uuuid': expenseUuuid,
    'file_name': fileName,
    'saved_path': savedPath,
  };
}

/// 构造 KPI 汇总 JSON。
Map<String, dynamic> fakeSummaryMap({
  double totalAmount = 50000.0,
  double pendingAmount = 12000.0,
  int totalCount = 42,
  int pendingCount = 15,
}) {
  return {
    'total_amount': totalAmount,
    'pending_amount': pendingAmount,
    'total_count': totalCount,
    'pending_count': pendingCount,
  };
}
