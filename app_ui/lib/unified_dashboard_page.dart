import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'config.dart';
import 'logger.dart';
import 'dart:ui';

/// 单页融合财务驾驶舱 — Master-Detail Dashboard
///
/// 顶部：KPI 指标 + 热力图 + 双维分析（项目进度条 + 类型环形图）
/// 下方：业务流水表格（左） + PDF 发票预览（右）
class UnifiedDashboardPage extends StatefulWidget {
  const UnifiedDashboardPage({super.key});

  @override
  State<UnifiedDashboardPage> createState() => _UnifiedDashboardPageState();
}

class _UnifiedDashboardPageState extends State<UnifiedDashboardPage> {
  // ═══════════════════════════════════════════════════════════════════
  // 数据容器
  // ═══════════════════════════════════════════════════════════════════
  Map<String, dynamic> _summary = {
    'total_amount': 0.0,
    'pending_amount': 0.0,
    'invoice_count': 0,
  };
  List<dynamic> _heatmap = [];
  List<dynamic> _distribution = []; // 按 project_name 分布
  List<dynamic> _typeDistribution = []; // 按 expense_type 分布
  List<dynamic> _expenses = [];

  // ═══════════════════════════════════════════════════════════════════
  // UI 状态
  // ═══════════════════════════════════════════════════════════════════
  bool _isLoading = true;
  bool _isPrivacyHidden = false;
  String? _selectedExpenseUuid;
  List<dynamic> _selectedInvoices = [];
  int _selectedInvoiceIndex = 0;
  bool _isDragging = false;

  // ═══════════════════════════════════════════════════════════════════
  // 搜索与筛选
  // ═══════════════════════════════════════════════════════════════════
  final TextEditingController _searchController = TextEditingController();
  String? _statusFilter;

  // ═══════════════════════════════════════════════════════════════════
  // 新增表单控制器
  // ═══════════════════════════════════════════════════════════════════
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  final _projectController = TextEditingController();
  final _typeController = TextEditingController();

  // ── 辅助：从已有数据中提取去重后的 project_name / expense_type 作为下拉建议 ──
  List<String> get _existingProjects {
    return _expenses
        .map((e) => e['project_name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> get _existingTypes {
    return _expenses
        .map((e) => e['expense_type']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _amountController.dispose();
    _dateController.dispose();
    _projectController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📡 数据获取
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _fetchAllData() async {
    setState(() => _isLoading = true);

    final base = AppConfig.baseUrl;
    const maxRetries = 3;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final results = await Future.wait([
          http.get(Uri.parse('$base/api/dashboard/summary')),
          http.get(Uri.parse('$base/api/dashboard/heatmap')),
          http.get(Uri.parse('$base/api/dashboard/distribution')),
          http.get(Uri.parse('$base/api/dashboard/type-distribution')),
          http.get(Uri.parse('$base/api/expenses/?limit=200')),
        ]);

        if (results.every((r) => r.statusCode == 200)) {
          setState(() {
            _summary = json.decode(utf8.decode(results[0].bodyBytes));
            _heatmap = json.decode(utf8.decode(results[1].bodyBytes));
            _distribution = json.decode(utf8.decode(results[2].bodyBytes));
            _typeDistribution = json.decode(utf8.decode(results[3].bodyBytes));
            _expenses = json.decode(utf8.decode(results[4].bodyBytes));
            _isLoading = false;
          });
          return;
        }
        // 非 200 状态码，等一会儿重试
        if (attempt < maxRetries - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        AppLogger.error('获取驾驶舱数据失败 (第${attempt + 1}次)', e);
        if (attempt < maxRetries - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    // 重试全部失败
    setState(() => _isLoading = false);
  }

  Future<void> _fetchExpenses() async {
    try {
      final Map<String, String> params = {'limit': '200'};
      final search = _searchController.text.trim();
      if (search.isNotEmpty) params['search'] = search;
      if (_statusFilter != null) params['status'] = _statusFilter!;

      final uri = Uri.parse(
        '${AppConfig.baseUrl}/api/expenses/',
      ).replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        setState(() {
          _expenses = json.decode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      _showSnackBar('获取流水数据失败: $e', isError: true);
    }
  }

  Future<void> _fetchBoundInvoices(String expenseId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/by-expense/$expenseId'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _selectedInvoices = json.decode(utf8.decode(response.bodyBytes));
          _selectedInvoiceIndex = 0;
        });
      }
    } catch (e) {
      AppLogger.error('获取历史发票失败', e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📝 CRUD 操作
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _addExpense() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/expenses/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': _titleController.text.trim(),
          'amount': double.parse(_amountController.text.trim()),
          'incurred_date': _dateController.text.trim(),
          'status': '待开票',
          'project_name': _projectController.text.trim().isEmpty
              ? null
              : _projectController.text.trim(),
          'expense_type': _typeController.text.trim().isEmpty
              ? null
              : _typeController.text.trim(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSnackBar('新增业务流水成功');
        if (mounted) Navigator.pop(context);
        _clearForm();
        _fetchAllData(); // 刷新全部数据以更新 KPI + 热力图 + 分布图
      } else {
        throw Exception('提交失败: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('新增失败: $e', isError: true);
    }
  }

  void _clearForm() {
    _titleController.clear();
    _amountController.clear();
    _dateController.clear();
    _projectController.clear();
    _typeController.clear();
  }

  Future<void> _updateExpenseStatus(String uuuid, String nextStatus) async {
    try {
      final response = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/api/expenses/$uuuid'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'status': nextStatus}),
      );

      if (response.statusCode == 200) {
        _showSnackBar('状态已成功推进至 [$nextStatus]');
        _fetchAllData();
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar('更新失败: ${err['detail']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('推进状态失败: $e', isError: true);
    }
  }

  Future<void> _deleteExpense(String uuuid) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/expenses/$uuuid'),
      );
      if (response.statusCode == 200) {
        _showSnackBar('记录已成功彻底删除');
        // 如果删除的是当前选中的行，清空右侧 PDF 面板
        if (_selectedExpenseUuid == uuuid) {
          setState(() {
            _selectedExpenseUuid = null;
            _selectedInvoices = [];
          });
        }
        _fetchAllData();
      } else {
        throw Exception('后端删除失败: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('删除请求异常: $e', isError: true);
    }
  }

  Future<void> _bindInvoice(String filePath) async {
    final expenseId = _selectedExpenseUuid;
    if (expenseId == null) return;

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/bind'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'expense_uuuid': expenseId,
          'source_file_path': filePath,
        }),
      );

      if (response.statusCode == 201) {
        _showSnackBar('发票绑定成功！');
        _fetchBoundInvoices(expenseId);
      } else {
        final error = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar('绑定失败: ${error['detail']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('网络请求失败: $e', isError: true);
    }
  }

  Future<void> _deleteInvoice(String invoiceUuid) async {
    // 先释放 PDF 文件锁
    setState(() => _selectedInvoiceIndex = -1);
    await Future.delayed(const Duration(milliseconds: 150));

    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/$invoiceUuid'),
      );
      if (response.statusCode == 200) {
        _showSnackBar('发票已解绑并删除');
        final expenseId = _selectedExpenseUuid;
        if (expenseId != null) _fetchBoundInvoices(expenseId);
      } else {
        _showSnackBar('解绑失败', isError: true);
      }
    } catch (e) {
      _showSnackBar('网络请求失败: $e', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🎨 UI 辅助方法
  // ═══════════════════════════════════════════════════════════════════

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 状态 → 颜色映射
  Color _statusColor(String status) {
    switch (status) {
      case '待开票':
        return Colors.orange;
      case '已开票':
        return Colors.green;
      case '待报销':
        return Colors.amber.shade700;
      case '核销中':
        return Colors.blue;
      case '已完结':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  /// 弹出删除确认框
  void _showDeleteConfirmation(String uuuid, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('确认删除流水？'),
          ],
        ),
        content: Text('你确定要删除事由为"$title"的这条流水记录吗？此操作不可逆！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteExpense(uuuid);
            },
            child: const Text('确认删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 新增开销 Dialog — 含 project_name / expense_type 的 Autocomplete 选择
  void _showAddExpenseDialog() {
    _clearForm();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white.withValues(alpha: 0.95),
            title: const Text(
              '新增业务开销记录',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 事由
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: '事由 / 开销名称 *',
                        prefixIcon: Icon(Icons.edit_note),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入事由' : null,
                    ),
                    const SizedBox(height: 14),
                    // 金额
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '金额 (元) *',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '请输入金额';
                        if (double.tryParse(v.trim()) == null) return '请输入合法数字';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    // 日期
                    TextFormField(
                      controller: _dateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: '发生日期 *',
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null) {
                          final fmt =
                              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                          _dateController.text = fmt;
                        }
                      },
                      validator: (v) =>
                          (v == null || v.isEmpty) ? '请选择日期' : null,
                    ),
                    const SizedBox(height: 14),
                    // 开销项目 — Autocomplete
                    Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _existingProjects;
                        }
                        return _existingProjects.where(
                          (opt) => opt.toLowerCase().contains(
                            textEditingValue.text.toLowerCase(),
                          ),
                        );
                      },
                      onSelected: (val) => _projectController.text = val,
                      fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
                        // 同步外部 _projectController 的值
                        controller.text = _projectController.text;
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (v) => _projectController.text = v,
                          decoration: const InputDecoration(
                            labelText: '开销项目',
                            prefixIcon: Icon(Icons.folder_outlined),
                            hintText: '选择或输入项目名称',
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    // 开销类型 — Autocomplete
                    Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _existingTypes;
                        }
                        return _existingTypes.where(
                          (opt) => opt.toLowerCase().contains(
                            textEditingValue.text.toLowerCase(),
                          ),
                        );
                      },
                      onSelected: (val) => _typeController.text = val,
                      fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
                        controller.text = _typeController.text;
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (v) => _typeController.text = v,
                          decoration: const InputDecoration(
                            labelText: '开销类型',
                            prefixIcon: Icon(Icons.category_outlined),
                            hintText: '选择或输入类型（如差旅交通）',
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _clearForm();
                  Navigator.of(ctx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: _addExpense,
                child: const Text(
                  '提交保存',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🧱 玻璃质感卡片基础组件
  // ═══════════════════════════════════════════════════════════════════
  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    BorderRadiusGeometry? borderRadius,
  }) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: borderRadius ?? BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📊 顶部驾驶舱组件
  // ═══════════════════════════════════════════════════════════════════

  /// 左侧：核心 KPI + 隐私切换
  Widget _buildKpiCard() {
    // 逻辑计算保持不变...
    double pendingReimburse = _expenses
        .where((e) => e['status'] == '待报销' || e['status'] == '核销中')
        .fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());
    double yearTotal = (_summary['total_amount'] as num).toDouble();
    double monthTotal = _expenses
        .where((e) {
          final d = e['incurred_date']?.toString() ?? '';
          final now = DateTime.now();
          return d.startsWith(
            '${now.year}-${now.month.toString().padLeft(2, '0')}',
          );
        })
        .fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());
    double pending = (_summary['pending_amount'] as num).toDouble();

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '核心财务指标',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              GestureDetector(
                onTap: () =>
                    setState(() => _isPrivacyHidden = !_isPrivacyHidden),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _isPrivacyHidden ? '127.0.0.1' : '127.0.0.1:18090',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          // 还原 HTML grid-template-columns: 1fr 1fr; gap: 12px;
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: _kpiTile(
                    '本月累计 (元)',
                    monthTotal,
                    trend: '↑ 15%',
                    trendUp: true,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiTile(
                    '待开票 (元)',
                    pending,
                    trend: '↓ 8%',
                    trendUp: false,
                    color: const Color(0xFFEA580C),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: _kpiTile(
                    '核销中 (元)',
                    pendingReimburse,
                    trend: '↑ 2%',
                    trendUp: true,
                    color: const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiTile(
                    '年度总计 (元)',
                    yearTotal,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiTile(String title, double value, {String? trend, bool trendUp = true, Color color = const Color(0xFF4F46E5)}) {
    final display = _isPrivacyHidden ? '****' : value.toStringAsFixed(2);
    
    // 关键修复：把 FittedBox 提到了最外层！
    // 这样无论是金额太长（横向），还是由于 Windows 字体缩放导致偏高（纵向）
    // 它都会像矢量图(SVG)一样，整体完美平滑地缩小，绝对不会出现黄黑警告条。
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          // 内部的 Row 照常排列即可，外层的 FittedBox 会罩着它
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(display, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color, fontFamily: 'Consolas')),
              if (trend != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: trendUp ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(trend, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: trendUp ? const Color(0xFFEF4444) : const Color(0xFF10B981))),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 中间：开销频次热力图
  Widget _buildHeatmapCard() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '业务发生频次 (近3个月)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _heatmap.isEmpty
                ? const Center(
                    child: Text(
                      '暂无数据',
                      style: TextStyle(color: Colors.black38),
                    ),
                  )
                : GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 24,
                          childAspectRatio: 1,
                          crossAxisSpacing: 3,
                          mainAxisSpacing: 3,
                        ),
                    itemCount: _heatmap.length.clamp(0, 90),
                    itemBuilder: (ctx, i) {
                      final count = (_heatmap[i]['count'] as int?) ?? 0;
                      Color bg;
                      if (count == 0) {
                        bg = const Color(0xFFE2E8F0);
                      } else if (count <= 1) {
                        bg = const Color(0xFFC7D2FE);
                      } else if (count <= 3) {
                        bg = const Color(0xFF818CF8);
                      } else if (count <= 6) {
                        bg = const Color(0xFF4F46E5);
                      } else {
                        bg = const Color(0xFF312E81);
                      }
                      return _AnimatedHeatmapBox(
                        tooltip: '${_heatmap[i]['date']}: $count 笔',
                        color: bg,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 右侧：双维分析（项目进度条 + 类型环形图）
  Widget _buildDualAnalysisCard() {
    // Top 3 项目
    final top3 = _distribution.take(3).toList();
    final maxAmt = top3.isNotEmpty
        ? top3
              .map((d) => (d['amount'] as num).toDouble())
              .reduce((a, b) => a > b ? a : b)
        : 1.0;

    // 环形图颜色
    final donutColors = const [
      Color(0xFF4F46E5),
      Color(0xFF0EA5E9),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
    ];

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '多维开销分析 (本月)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                // 左半：项目进度条
                Expanded(
                  flex: 12,
                  child: top3.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无数据',
                            style: TextStyle(
                              color: Colors.black38,
                              fontSize: 11,
                            ),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: top3.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final data = entry.value;
                            final pct = maxAmt > 0
                                ? ((data['amount'] as num).toDouble() / maxAmt)
                                : 0.0;
                            final barColors = [
                              const Color(0xFF4F46E5),
                              const Color(0xFF0EA5E9),
                              const Color(0xFF10B981),
                            ];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        data['category']?.toString() ?? '-',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      Text(
                                        '${(pct * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 6,
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        barColors[idx % barColors.length],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
                // 分割线
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: Colors.black.withValues(alpha: 0.05),
                ),
                // 右半：环形图
                Expanded(
                  flex: 8,
                  child: _typeDistribution.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无数据',
                            style: TextStyle(
                              color: Colors.black38,
                              fontSize: 11,
                            ),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 70,
                              height: 70,
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 22,
                                  sections: _typeDistribution
                                      .asMap()
                                      .entries
                                      .map((entry) {
                                        final i = entry.key;
                                        final d = entry.value;
                                        return PieChartSectionData(
                                          color:
                                              donutColors[i %
                                                  donutColors.length],
                                          value:
                                              (d['percentage'] as num)
                                                  .toDouble() *
                                              100,
                                          title: '',
                                          radius: 14,
                                        );
                                      })
                                      .toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // 图例
                            Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              alignment: WrapAlignment.center,
                              children: _typeDistribution.asMap().entries.map((
                                entry,
                              ) {
                                final i = entry.key;
                                final d = entry.value;
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color:
                                            donutColors[i % donutColors.length],
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      d['category']?.toString() ?? '-',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📋 下方业务区 — 左侧表格
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildTablePanel() {
    return _glassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 工具栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  '流水明细',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 16),
                // 搜索框 — 移到标题右侧
                SizedBox(
                  width: 180,
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: '搜索事由、项目或金额...',
                      hintStyle: const TextStyle(fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      isDense: true,
                    ),
                    onChanged: (_) => _fetchExpenses(),
                  ),
                ),
                const SizedBox(width: 8),
                // 状态筛选 — 紧跟搜索框
                SizedBox(
                  height: 34,
                  child: DropdownButton<String>(
                    value: _statusFilter ?? '全部',
                    underline: const SizedBox(),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    items: ['全部', '待开票', '已开票', '待报销', '核销中', '已完结']
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() => _statusFilter = v == '全部' ? null : v);
                      _fetchExpenses();
                    },
                  ),
                ),
                const Spacer(),
                // 选中行时出现删除按钮
                if (_selectedExpenseUuid != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('删除', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        final exp = _expenses.firstWhere(
                          (e) => e['uuuid'] == _selectedExpenseUuid,
                          orElse: () => {'title': '未知'},
                        );
                        _showDeleteConfirmation(
                          _selectedExpenseUuid!,
                          exp['title']?.toString() ?? '未知',
                        );
                      },
                    ),
                  ),
                // 新增按钮
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增开销', style: TextStyle(fontSize: 12)),
                  onPressed: _showAddExpenseDialog,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 数据表格
          Expanded(
            child: _expenses.isEmpty
                ? const Center(
                    child: Text(
                      '暂无匹配的开销记录流水',
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                    ),
                  )
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xFFF8FAFC),
                        ),
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 52,
                        columnSpacing: 20,
                        columns: const [
                          // 给表头加上 11px 的占位，完美对齐下方带左侧蓝条的文字
                          DataColumn(
                            label: Row(
                              children: [
                                SizedBox(width: 11),
                                Text(
                                  '发生日期',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              '开销项目',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              '开销类型',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              '开销事由',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DataColumn(
                            numeric: true,
                            label: Text(
                              '金额 (¥)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              '状态',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                        rows: _expenses.map((expense) {
                          final uuuid = expense['uuuid']?.toString() ?? '';
                          final title = expense['title']?.toString() ?? '无事由';
                          final status = expense['status']?.toString() ?? '待开票';
                          final project =
                              expense['project_name']?.toString() ?? '-';
                          final type =
                              expense['expense_type']?.toString() ?? '-';
                          final date =
                              expense['incurred_date']?.toString() ?? '-';
                          final amount =
                              (expense['amount'] as num?)?.toDouble() ?? 0;
                          final isActive = uuuid == _selectedExpenseUuid;
                          final statusClr = _statusColor(status);

                          return DataRow(
                            selected: isActive,
                            color: WidgetStateProperty.resolveWith<Color?>((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return const Color(0xFFEEF2FF);
                              }
                              if (states.contains(WidgetState.hovered)) {
                                return Colors.white.withValues(alpha: 0.8);
                              }
                              return null;
                            }),
                            onSelectChanged: (_) {
                              setState(() {
                                _selectedExpenseUuid = uuuid;
                                _selectedInvoices = [];
                                _selectedInvoiceIndex = 0;
                              });
                              _fetchBoundInvoices(uuuid);
                            },
                            cells: [
                              DataCell(
                                Row(
                                  children: [
                                    // 用透明色占位，保证选中和未选中时文字绝对对齐
                                    Container(
                                      width: 3,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? const Color(0xFF4F46E5)
                                            : Colors.transparent,
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                              right: Radius.circular(2),
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        date,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Text(
                                  project,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: const Color(0xFF334155),
                                    fontWeight: project != '-'
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              DataCell(_typeTag(type)),
                              DataCell(
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF64748B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DataCell(
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    _isPrivacyHidden
                                        ? '****'
                                        : amount.toStringAsFixed(2),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'Consolas', // 对齐 HTML 等宽字体
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                _statusDropdown(uuuid, status, statusClr),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 开销类型彩色标签
  Widget _typeTag(String type) {
    Color bg;
    Color fg;
    switch (type) {
      case '差旅交通':
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0284C7);
        break;
      case '云服务采购':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF059669);
        break;
      case '招待':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  /// 状态标签（非终态时作为 PopupMenuButton 触发器）
  Widget _statusDropdown(String uuuid, String status, Color color) {
    final nextStatuses = _getNextStatuses(status);

    // 终态或无可转换状态 → 纯标签
    if (nextStatuses.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
    }

    // 有可转换状态 → 可点击展开下拉
    final nextClrs = [Colors.green, Colors.blue, Colors.orange, Colors.purple];

    return PopupMenuButton<String>(
      offset: const Offset(0, 32),
      padding: EdgeInsets.zero,
      onSelected: (next) => _updateExpenseStatus(uuuid, next),
      itemBuilder: (_) => nextStatuses.asMap().entries.map((entry) {
        return PopupMenuItem<String>(
          value: entry.value,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_forward_ios,
                size: 12,
                color: nextClrs[entry.key % nextClrs.length],
              ),
              const SizedBox(width: 6),
              Text(
                '转为「${entry.value}」',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: nextClrs[entry.key % nextClrs.length],
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_drop_down, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  /// 获取当前状态的合法下一状态列表（对应后端 VALID_TRANSITIONS）
  List<String> _getNextStatuses(String currentStatus) {
    switch (currentStatus) {
      case '待开票':
        return ['已开票'];
      case '已开票':
        return ['待报销'];
      case '待报销':
        return ['核销中'];
      case '核销中':
        return ['已完结'];
      default:
        return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📄 下方业务区 — 右侧 PDF 预览面板
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildPdfPanel() {
    // 计算当前可预览的 PDF 路径
    String? previewPath;
    if (_selectedInvoices.isNotEmpty &&
        _selectedInvoiceIndex >= 0 &&
        _selectedInvoiceIndex < _selectedInvoices.length) {
      previewPath =
          _selectedInvoices[_selectedInvoiceIndex]['saved_path'] as String?;
    }

    return _glassCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          // ── 发票缩略图条 ──
          if (_selectedInvoices.isNotEmpty && _selectedInvoiceIndex >= 0)
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _selectedInvoices.length,
                separatorBuilder: (_, _) =>
                    const VerticalDivider(width: 1, color: Colors.black12),
                itemBuilder: (ctx, i) {
                  final inv = _selectedInvoices[i];
                  final isActive = i == _selectedInvoiceIndex;
                  return InkWell(
                    onTap: () => setState(() => _selectedInvoiceIndex = i),
                    child: Container(
                      color: isActive
                          ? Colors.blue.withValues(alpha: 0.1)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.picture_as_pdf,
                            size: 16,
                            color: isActive ? Colors.blue : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              inv['file_name']?.toString() ?? '未知',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 14),
                            color: Colors.redAccent,
                            tooltip: '解绑删除',
                            onPressed: () => _deleteInvoice(inv['uuuid']),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          // ── PDF 内容区 ──
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              onDragDone: (details) async {
                setState(() => _isDragging = false);
                if (_selectedExpenseUuid == null) {
                  _showSnackBar('请先在左侧列表中选择一笔业务流水！', isError: true);
                  return;
                }
                final file = details.files.first;
                if (!file.path.toLowerCase().endsWith('.pdf')) {
                  _showSnackBar('目前仅支持绑定 PDF 格式的发票！', isError: true);
                  return;
                }
                await _bindInvoice(file.path);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _isDragging
                      ? Colors.blue.withValues(alpha: 0.15)
                      : const Color(0xFF525659).withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  border: _isDragging
                      ? Border.all(color: Colors.blue, width: 2)
                      : null,
                ),
                child: previewPath != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12),
                        ),
                        child: SfPdfViewer.file(File(previewPath)),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 64,
                              color: _isDragging
                                  ? Colors.blue
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedExpenseUuid == null
                                  ? '请点击左侧列表查看发票原件'
                                  : '将 PDF 发票拖拽到此处绑定',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_selectedExpenseUuid != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '（支持 .pdf 格式文件）',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🏗️ build()
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
            end: Alignment.bottomRight, // 对应 HTML 135deg
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0), // 完全对齐 HTML padding: 16px 20px
          child: Column(
            children: [
              // ── 顶部驾驶舱 ──
              SizedBox(
                height: 170, // 完美还原 HTML height: 170px
                child: Row(
                  children: [
                    Expanded(flex: 25, child: _buildKpiCard()),
                    const SizedBox(width: 16), // 还原 HTML gap: 16px
                    Expanded(flex: 40, child: _buildHeatmapCard()),
                    const SizedBox(width: 16),
                    Expanded(flex: 35, child: _buildDualAnalysisCard()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ── 下方业务区 ──
              Expanded(
                child: Row(
                  children: [
                    Expanded(flex: 65, child: _buildTablePanel()),
                    const SizedBox(width: 16),
                    Expanded(flex: 35, child: _buildPdfPanel()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
/// 热力图动画方块 — 还原 HTML 的 hover scale(1.3) + 阴影浮起效果
// ═══════════════════════════════════════════════════════════════════════════════
class _AnimatedHeatmapBox extends StatefulWidget {
  final Color color;
  final String tooltip;
  const _AnimatedHeatmapBox({required this.color, required this.tooltip});

  @override
  State<_AnimatedHeatmapBox> createState() => _AnimatedHeatmapBoxState();
}

class _AnimatedHeatmapBoxState extends State<_AnimatedHeatmapBox> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _isHovered ? 1.3 : 1.0;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.diagonal3Values(scale, scale, 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(_isHovered ? 4 : 2),
            boxShadow: _isHovered
                ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
                : [],
          ),
        ),
      ),
    );
  }
}
