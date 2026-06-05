import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/expense_service.dart';
import 'widgets/kpi_summary_card.dart';
import 'widgets/heatmap_card.dart';
import 'widgets/dual_analysis_card.dart';
import 'widgets/expense_table_panel.dart';
import 'widgets/invoice_pdf_panel.dart';
import 'widgets/batch_upload_dialog.dart';
import '../../logger.dart';
import '../../main.dart' show backendReady;

/// 单页融合财务驾驶舱 — 骨架编排页 (Orchestrator)
///
/// 仅持有核心状态变量和生命周期，所有 UI 细节已拆分为独立组件。
/// 业务数据通过 [ExpenseService] 统一获取，回调绑定到各子组件。
class UnifiedDashboardPage extends StatefulWidget {
  const UnifiedDashboardPage({super.key});

  @override
  State<UnifiedDashboardPage> createState() => _UnifiedDashboardPageState();
}

class _UnifiedDashboardPageState extends State<UnifiedDashboardPage> {
  // ═══════════════════════════════════════════════════════════════════
  // 📦 核心状态
  // ═══════════════════════════════════════════════════════════════════
  Map<String, dynamic> _summary = {};
  List<dynamic> _heatmap = [];
  List<dynamic> _distribution = [];
  List<dynamic> _typeDistribution = [];
  List<dynamic> _expenses = [];

  bool _isLoading = true;
  bool _isPrivacyHidden = false;

  String? _selectedExpenseUuid;
  Set<String> _selectedUuuids = {};
  List<dynamic> _selectedInvoices = [];
  int _selectedInvoiceIndex = 0;

  String _analysisTimeRange = '近30天';
  String? _dateFrom;
  String? _dateTo;

  final TextEditingController _searchController = TextEditingController();
  String? _statusFilter;

  /// 搜索防抖定时器 — 用户停止输入 300ms 后才发起 API 请求
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // 延迟启动：等待后端 HTTP 服务完全就绪后再发请求
    _initAfterBackendReady();
  }

  Future<void> _initAfterBackendReady() async {
    try {
      await backendReady;
    } catch (_) {
      // 后端启动失败或超时 — 仍然尝试请求（让用户看到错误而非空白）
    }
    if (mounted) _fetchAllData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── 搜索防抖：用户停止输入 300ms 后才触发请求 ──
  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _fetchExpenses();
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📡 数据获取（全部通过 ExpenseService）
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _fetchAllData() async {
    if (_expenses.isEmpty) {
      setState(() => _isLoading = true);
    }

    // ── 第一步：先加载流水列表（最快），立即渲染表格 ──
    try {
      final expenses = await ExpenseService.fetchExpenses();
      if (mounted) setState(() { _expenses = expenses; _isLoading = false; });
    } catch (e) {
      AppLogger.error('获取流水列表失败', e);
      if (mounted) setState(() => _isLoading = false);
    }

    // ── 第二步：异步加载看板数据（KPI / 热力图 / 分布图），不阻塞 UI ──
    try {
      final days = DualAnalysisCard.daysFor(_analysisTimeRange);
      final results = await Future.wait([
        ExpenseService.fetchDashboardSummary(),
        ExpenseService.fetchHeatmapData(),
        ExpenseService.fetchDistributionData(days: days),
        ExpenseService.fetchTypeDistributionData(days: days),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _heatmap = results[1] as List<dynamic>;
        _distribution = results[2] as List<dynamic>;
        _typeDistribution = results[3] as List<dynamic>;
      });
    } catch (e) {
      AppLogger.error('获取看板数据失败', e);
    }
  }

  Future<void> _fetchExpenses() async {
    try {
      final data = await ExpenseService.fetchExpenses(
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        status: _statusFilter,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (mounted) setState(() => _expenses = data);
    } catch (e) {
      _snack('获取流水数据失败: $e', isError: true);
    }
  }

  /// 轻量刷新：仅拉取摘要 + 流水列表（新增/删除/状态变更后使用）
  /// 跳过热力图、分布图等聚合数据 — 单条记录的变更不影响这些图表
  Future<void> _refreshSummaryAndExpenses() async {
    try {
      final results = await Future.wait([
        ExpenseService.fetchDashboardSummary(),
        ExpenseService.fetchExpenses(
          search: _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
          status: _statusFilter,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _expenses = results[1] as List<dynamic>;
      });
    } catch (e) {
      AppLogger.error('刷新摘要和列表失败', e);
    }
  }

  Future<void> _fetchBoundInvoices(String expenseUuuid) async {
    try {
      final data = await ExpenseService.fetchBoundInvoices(expenseUuuid);
      if (mounted) {
        setState(() {
          _selectedInvoices = data;
          _selectedInvoiceIndex = 0;
        });
      }
    } catch (e) {
      AppLogger.error('获取历史发票失败', e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔔 回调 — 表格面板
  // ═══════════════════════════════════════════════════════════════════

  void _onSelectRow(String uuuid) {
    if (_selectedExpenseUuid == uuuid) {
      // 点击已选中行 → 取消选中，清空 PDF 面板
      setState(() {
        _selectedExpenseUuid = null;
        _selectedInvoices = [];
        _selectedInvoiceIndex = 0;
      });
      return;
    }
    setState(() {
      _selectedExpenseUuid = uuuid;
      _selectedInvoices = [];
      _selectedInvoiceIndex = 0;
    });
    _fetchBoundInvoices(uuuid);
  }

  void _onMultiSelectChanged(Set<String> uuuids) {
    setState(() {
      _selectedUuuids = uuuids;
      if (uuuids.isEmpty || (_selectedExpenseUuid != null && !uuuids.contains(_selectedExpenseUuid))) {
        _selectedExpenseUuid = null;
        _selectedInvoices = [];
        _selectedInvoiceIndex = 0;
      }
    });
  }

  Future<void> _onBatchUpdateStatus(
      Set<String> uuuids, String nextStatus) async {
    final results = await Future.wait(
      uuuids.map((id) => ExpenseService.updateExpenseStatus(id, nextStatus)
          .then((_) => true, onError: (e) {
            AppLogger.error('批量更新失败 uuuid=$id', e);
            return false;
          })),
    );
    final success = results.where((r) => r).length;
    _snack('批量更新完成: $success / ${uuuids.length} 条');
    setState(() => _selectedUuuids = {});
    _refreshSummaryAndExpenses();
  }

  Future<void> _onBlockExpense(String uuuid) async {
    try {
      await ExpenseService.blockExpense(uuuid);
    } catch (e) {
      AppLogger.error('屏蔽失败 uuuid=$uuuid', e);
    }
  }

  Future<void> _onUnblockExpense(String uuuid) async {
    try {
      await ExpenseService.unblockExpense(uuuid);
    } catch (e) {
      AppLogger.error('取消屏蔽失败 uuuid=$uuuid', e);
    }
  }

  Future<void> _onUpdateStatus(String uuuid, String nextStatus) async {
    try {
      await ExpenseService.updateExpenseStatus(uuuid, nextStatus);
      _snack('状态已成功推进至 [$nextStatus]');
      _refreshSummaryAndExpenses();
    } catch (e) {
      _snack('推进状态失败: $e', isError: true);
    }
  }

  Future<void> _onDeleteExpense(String uuuid) async {
    try {
      await ExpenseService.deleteExpense(uuuid);
      _snack('记录已成功彻底删除');
      if (_selectedExpenseUuid == uuuid) {
        setState(() {
          _selectedExpenseUuid = null;
          _selectedInvoices = [];
        });
      }
      _refreshSummaryAndExpenses();
    } catch (e) {
      _snack('删除请求异常: $e', isError: true);
    }
  }

  void _onStatusFilterChanged(String? status) {
    setState(() => _statusFilter = status);
    _fetchExpenses();
  }

  void _onDateRangeChanged(String? from, String? to) {
    setState(() {
      _dateFrom = from;
      _dateTo = to;
    });
    _fetchExpenses();
  }

  /// 时间范围下拉变更 → 自动联动明细表日期区间
  void _onTimeRangeChanged(String? range) {
    if (range == null) return;
    final dr = DualAnalysisCard.dateRangeFor(range);
    setState(() {
      _analysisTimeRange = range;
      _dateFrom = dr?.from;
      _dateTo = dr?.to;
    });
    _fetchAllData();
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔔 回调 — PDF 面板
  // ═══════════════════════════════════════════════════════════════════

  void _onInvoiceIndexChanged(int index) {
    setState(() => _selectedInvoiceIndex = index);
  }

  Future<void> _onInvoiceDeleted(String invoiceUuuid) async {
    try {
      await ExpenseService.deleteInvoice(invoiceUuuid);
      _snack('发票已解绑并删除');
      if (_selectedExpenseUuid != null) {
        _fetchBoundInvoices(_selectedExpenseUuid!);
      }
    } catch (e) {
      _snack('解绑失败: $e', isError: true);
    }
  }

  Future<void> _onInvoiceFilesDropped(List<String> paths) async {
    if (_selectedExpenseUuid != null) {
      // ── 模式 1：绑定到已选中条目（仅取第一个文件） ──
      try {
        await ExpenseService.bindInvoice(_selectedExpenseUuid!, paths.first);
        _snack('发票绑定成功！');
        _fetchBoundInvoices(_selectedExpenseUuid!);
      } catch (e) {
        _snack('绑定失败: $e', isError: true);
      }
      return;
    }

    // ── 模式 2：批量全自动建档 — 先收集用户填写的项目/类型 ──
    if (!mounted) return;
    final batchInfo = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchInfoDialog(
        existingProjects: _existingProjectNames,
        existingTypes: _existingTypeNames,
      ),
    );
    if (batchInfo == null || !mounted) return; // 用户取消了

    // 弹出毛玻璃加载弹窗
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black38,
      builder: (_) => BatchUploadDialog(total: paths.length),
    );

    final projectName = batchInfo['project_name'] ?? '';
    final expenseType = batchInfo['expense_type'] ?? '';

    int success = 0;
    int fail = 0;
    String? firstNewUuid;
    for (int i = 0; i < paths.length; i++) {
      try {
        final result = await ExpenseService.bindInvoiceAuto(
          paths[i],
          projectName: projectName.isEmpty ? null : projectName,
          expenseType: expenseType.isEmpty ? null : expenseType,
        );
        firstNewUuid ??= result['expense_uuuid']?.toString();
        success++;
      } catch (e) {
        AppLogger.error('自动建档失败 | file=${paths[i]}', e);
        fail++;
      }
    }

    // 关闭加载弹窗
    if (mounted) Navigator.of(context).pop();
    _snack('批量导入完成：成功 $success 条，失败 $fail 条');
    _refreshSummaryAndExpenses();

    // 自动选中第一条新记录，让 PDF 面板立即显示发票
    if (firstNewUuid != null && mounted) {
      setState(() => _selectedExpenseUuid = firstNewUuid);
      _fetchBoundInvoices(firstNewUuid);
    }
  }

  List<String> get _existingProjectNames {
    final names = _expenses
        .map((e) => e['project_name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  List<String> get _existingTypeNames {
    final types = _expenses
        .map((e) => e['expense_type']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    types.sort();
    return types;
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🏗️ build
  // ═══════════════════════════════════════════════════════════════════

  /// KPI 预计算 getter — 单次遍历提取四项指标，避免在 build 中重复遍历
  ({double monthTotal, double pending, double pendingReimburse, double yearTotal}) get _kpi {
    final now = DateTime.now();
    final cutoff30 = now.subtract(const Duration(days: 30));
    final cutoffStr =
        '${cutoff30.year}-${cutoff30.month.toString().padLeft(2, '0')}-${cutoff30.day.toString().padLeft(2, '0')}';
    double monthTotal = 0;
    double pendingReimburse = 0;
    for (final e in _expenses) {
      final amt = (e['amount'] as num).toDouble();
      final status = e['status']?.toString() ?? '';
      if (status == '待报销' || status == '核销中') pendingReimburse += amt;
      if ((e['incurred_date']?.toString() ?? '').compareTo(cutoffStr) >= 0) monthTotal += amt;
    }
    return (
      monthTotal: monthTotal,
      pending: (_summary['pending_amount'] as num?)?.toDouble() ?? 0,
      pendingReimburse: pendingReimburse,
      yearTotal: (_summary['total_amount'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE2E8F0), Color(0xFFF8FAFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── 顶部驾驶舱 (RepaintBoundary 隔离，避免明细表刷新时重绘图表) ──
              RepaintBoundary(
                child: SizedBox(
                height: 170,
                child: Row(
                  children: [
                    Expanded(
                      flex: 25,
                      child: KpiSummaryCard(
                        isPrivacyHidden: _isPrivacyHidden,
                        onPrivacyToggle: () =>
                            setState(() => _isPrivacyHidden = !_isPrivacyHidden),
                        monthTotal: _kpi.monthTotal,
                        pending: _kpi.pending,
                        pendingReimburse: _kpi.pendingReimburse,
                        yearTotal: _kpi.yearTotal,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 40,
                      child: HeatmapCard(heatmap: _heatmap),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 35,
                      child: DualAnalysisCard(
                        distribution: _distribution,
                        typeDistribution: _typeDistribution,
                        analysisTimeRange: _analysisTimeRange,
                        dateFrom: _dateFrom,
                        dateTo: _dateTo,
                        onTimeRangeChanged: _onTimeRangeChanged,
                        onDateRangeChanged: _onDateRangeChanged,
                      ),
                    ),
                  ],
                ),
                ),
              ),  // RepaintBoundary
              const SizedBox(height: 16),
              // ── 下方业务区 (RepaintBoundary 隔离) ──
              Expanded(
                child: RepaintBoundary(
                  child: Row(
                  children: [
                    Expanded(
                      flex: 65,
                      child: ExpenseTablePanel(
                        expenses: _expenses,
                        selectedUuuids: _selectedUuuids,
                        selectedExpenseUuid: _selectedExpenseUuid,
                        isPrivacyHidden: _isPrivacyHidden,
                        currentStatusFilter: _statusFilter,
                        searchController: _searchController,
                        onSelectRowChanged: _onSelectRow,
                        onMultiSelectChanged: _onMultiSelectChanged,
                        onUpdateStatus: _onUpdateStatus,
                        onBatchUpdateStatus: _onBatchUpdateStatus,
                        onBlockExpense: _onBlockExpense,
                        onUnblockExpense: _onUnblockExpense,
                        onDeleteExpense: _onDeleteExpense,
                        onAddExpenseSubmitted: _refreshSummaryAndExpenses,
                        onStatusFilterChanged: _onStatusFilterChanged,
                        onSearchChanged: _onSearchChanged,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 35,
                      child: InvoicePdfPanel(
                        selectedExpenseUuid: _selectedExpenseUuid,
                        selectedInvoices: _selectedInvoices,
                        selectedInvoiceIndex: _selectedInvoiceIndex,
                        onInvoiceIndexChanged: _onInvoiceIndexChanged,
                        onInvoiceDeleted: _onInvoiceDeleted,
                        onInvoiceFilesDropped: _onInvoiceFilesDropped,
                      ),
                    ),
                  ],
                ),
                ),  // RepaintBoundary
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔧 工具
  // ═══════════════════════════════════════════════════════════════════

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}

