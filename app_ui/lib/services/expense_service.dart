import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// 对公报销系统 — 网络服务层
///
/// 将页面中所有 `http` 请求、JSON 解码、异常捕获统一抽离，
/// 方法均为静态，入参 / 返回值类型严谨，使用统一拼写 `uuuid`。
class ExpenseService {
  static String get _base => AppConfig.baseUrl;

  // ═══════════════════════════════════════════════════════════════════
  // 📊 看板数据
  // ═══════════════════════════════════════════════════════════════════

  /// 获取 KPI 汇总卡片数据
  static Future<Map<String, dynamic>> fetchDashboardSummary() async {
    final resp = await http.get(Uri.parse('$_base/api/dashboard/summary'));
    _ensureSuccess(resp);
    return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// 获取近 90 天每日开销频次热力图数据
  static Future<List<dynamic>> fetchHeatmapData() async {
    final resp = await http.get(Uri.parse('$_base/api/dashboard/heatmap'));
    _ensureSuccess(resp);
    return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
  }

  /// 获取按 project_name 分组的开销分布（项目进度条用）
  static Future<List<dynamic>> fetchDistributionData() async {
    final resp = await http.get(Uri.parse('$_base/api/dashboard/distribution'));
    _ensureSuccess(resp);
    return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
  }

  /// 获取按 expense_type 分组的开销分布（环形图用）
  static Future<List<dynamic>> fetchTypeDistributionData() async {
    final resp =
        await http.get(Uri.parse('$_base/api/dashboard/type-distribution'));
    _ensureSuccess(resp);
    return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📋 业务流水
  // ═══════════════════════════════════════════════════════════════════

  /// 获取开销流水列表，支持搜索和状态筛选
  static Future<List<dynamic>> fetchExpenses({
    String? search,
    String? status,
  }) async {
    final params = <String, String>{'limit': '200'};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (status != null) params['status'] = status;

    final uri = Uri.parse('$_base/api/expenses/')
        .replace(queryParameters: params);
    final resp = await http.get(uri);
    _ensureSuccess(resp);
    return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
  }

  /// 新增一条开销记录
  ///
  /// [data] 需包含 title, amount, incurred_date, status 等字段。
  /// 返回 true 表示创建成功。
  static Future<bool> addExpense(Map<String, dynamic> data) async {
    final resp = await http.post(
      Uri.parse('$_base/api/expenses/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(data),
    );
    if (resp.statusCode == 200 || resp.statusCode == 201) return true;
    throw Exception('创建开销失败: ${resp.statusCode}');
  }

  /// 推进一条开销的状态
  ///
  /// [uuuid] 流水主键，[nextStatus] 目标状态（须符合后端白名单）
  static Future<bool> updateExpenseStatus(
      String uuuid, String nextStatus) async {
    final resp = await http.patch(
      Uri.parse('$_base/api/expenses/$uuuid'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'status': nextStatus}),
    );
    if (resp.statusCode == 200) return true;
    final err = json.decode(utf8.decode(resp.bodyBytes));
    throw Exception(err['detail'] ?? '状态更新失败: ${resp.statusCode}');
  }

  /// 物理删除一条开销记录（后端自动级联删除关联发票 + PDF）
  static Future<bool> deleteExpense(String uuuid) async {
    final resp = await http.delete(Uri.parse('$_base/api/expenses/$uuuid'));
    if (resp.statusCode == 200) return true;
    throw Exception('删除失败: ${resp.statusCode}');
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🧾 发票 PDF 绑定
  // ═══════════════════════════════════════════════════════════════════

  /// 查询某条流水绑定的所有发票
  static Future<List<dynamic>> fetchBoundInvoices(String expenseUuuid) async {
    final resp = await http.get(
      Uri.parse('$_base/api/invoices/by-expense/$expenseUuuid'),
    );
    _ensureSuccess(resp);
    return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
  }

  /// 将本地 PDF 文件绑定到指定流水
  static Future<bool> bindInvoice(
      String expenseUuuid, String sourceFilePath) async {
    final resp = await http.post(
      Uri.parse('$_base/api/invoices/bind'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'expense_uuuid': expenseUuuid,
        'source_file_path': sourceFilePath,
      }),
    );
    if (resp.statusCode == 201) return true;
    final err = json.decode(utf8.decode(resp.bodyBytes));
    throw Exception(err['detail'] ?? '绑定失败: ${resp.statusCode}');
  }

  /// 解绑并删除单张发票（含物理 PDF）
  static Future<bool> deleteInvoice(String invoiceUuuid) async {
    final resp =
        await http.delete(Uri.parse('$_base/api/invoices/$invoiceUuuid'));
    if (resp.statusCode == 200) return true;
    throw Exception('解绑失败: ${resp.statusCode}');
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔧 内部工具
  // ═══════════════════════════════════════════════════════════════════

  /// 统一校验 HTTP 200，非 200 一律抛异常
  static void _ensureSuccess(http.Response resp) {
    if (resp.statusCode != 200) {
      throw Exception('服务端返回 ${resp.statusCode}');
    }
  }
}
