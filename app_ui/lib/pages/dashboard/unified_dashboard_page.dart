import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/expense_service.dart';
import 'widgets/kpi_summary_card.dart';
import 'widgets/heatmap_card.dart';
import 'widgets/dual_analysis_card.dart';
import 'widgets/expense_table_panel.dart';
import 'widgets/invoice_pdf_panel.dart';
import '../../logger.dart';

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
    _fetchAllData();
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
    // 仅首次加载时显示 loading 动画，后续刷新静默更新
    if (_expenses.isEmpty) {
      setState(() => _isLoading = true);
    }
    const maxRetries = 3;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final days = DualAnalysisCard.daysFor(_analysisTimeRange);
        final results = await Future.wait([
          ExpenseService.fetchDashboardSummary(),
          ExpenseService.fetchHeatmapData(),
          ExpenseService.fetchDistributionData(days: days),
          ExpenseService.fetchTypeDistributionData(days: days),
          ExpenseService.fetchExpenses(),
        ]);
        if (!mounted) return;
        setState(() {
          _summary = results[0] as Map<String, dynamic>;
          _heatmap = results[1] as List<dynamic>;
          _distribution = results[2] as List<dynamic>;
          _typeDistribution = results[3] as List<dynamic>;
          _expenses = results[4] as List<dynamic>;
          _isLoading = false;
        });
        return;
      } catch (e) {
        AppLogger.error('获取驾驶舱数据失败 (第${attempt + 1}次)', e);
        if (attempt < maxRetries - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
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
    setState(() {
      _selectedExpenseUuid = uuuid;
      _selectedInvoices = [];
      _selectedInvoiceIndex = 0;
    });
    _fetchBoundInvoices(uuuid);
  }

  void _onMultiSelectChanged(Set<String> uuuids) {
    setState(() => _selectedUuuids = uuuids);
  }

  Future<void> _onBatchUpdateStatus(
      Set<String> uuuids, String nextStatus) async {
    int success = 0;
    for (final id in uuuids) {
      try {
        await ExpenseService.updateExpenseStatus(id, nextStatus);
        success++;
      } catch (e) {
        AppLogger.error('批量更新失败 uuuid=$id', e);
      }
    }
    _snack('批量更新完成: $success / ${uuuids.length} 条');
    setState(() => _selectedUuuids = {});
    _refreshSummaryAndExpenses();
  }

  Future<void> _onBlockExpense(String uuuid) async {
    try {
      await ExpenseService.blockExpense(uuuid);
      _snack('记录已屏蔽');
      _refreshSummaryAndExpenses();
    } catch (e) {
      _snack('屏蔽失败: $e', isError: true);
    }
  }

  Future<void> _onUnblockExpense(String uuuid) async {
    try {
      await ExpenseService.unblockExpense(uuuid);
      _snack('已取消屏蔽');
      _refreshSummaryAndExpenses();
    } catch (e) {
      _snack('取消屏蔽失败: $e', isError: true);
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
    setState(() => _analysisTimeRange = range);
    // 根据时间范围自动计算日期区间
    final dr = DualAnalysisCard.dateRangeFor(range);
    setState(() {
      _dateFrom = dr?.from;
      _dateTo = dr?.to;
    });
    // 刷新图表（带 days） + 明细（带日期区间）
    _fetchAllData();
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔔 回调 — PDF 面板
  // ═══════════════════════════════════════════════════════════════════

  void _onInvoiceIndexChanged(int index) {
    setState(() => _selectedInvoiceIndex = index);
  }

  Future<void> _onInvoiceDeleted(String invoiceUuuid) async {
    setState(() => _selectedInvoiceIndex = -1);
    await Future.delayed(const Duration(milliseconds: 150));
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

  Future<void> _onInvoiceFileDropped(String filePath) async {
    if (_selectedExpenseUuid == null) {
      _snack('请先在左侧列表中选择一笔业务流水！', isError: true);
      return;
    }
    try {
      await ExpenseService.bindInvoice(_selectedExpenseUuid!, filePath);
      _snack('发票绑定成功！');
      _fetchBoundInvoices(_selectedExpenseUuid!);
    } catch (e) {
      _snack('绑定失败: $e', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🏗️ build
  // ═══════════════════════════════════════════════════════════════════

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
                        expenses: _expenses,
                        summary: _summary,
                        isPrivacyHidden: _isPrivacyHidden,
                        onPrivacyToggle: () =>
                            setState(() => _isPrivacyHidden = !_isPrivacyHidden),
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
                        onInvoiceFileDropped: _onInvoiceFileDropped,
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
