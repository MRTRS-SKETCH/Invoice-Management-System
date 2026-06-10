import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/expense_service.dart';
import '../../../widgets/glass_card.dart';
import 'add_expense_dialog.dart';
import 'column_width_manager.dart';

/// 业务流水表格面板 — 搜索 / 筛选 / 全选 / 状态流转 / 删除 / 新增
///
/// 支持列宽拖拽调整，内容居中自动换行，发票类型以图标呈现。
class ExpenseTablePanel extends StatefulWidget {
  final List<dynamic> expenses;
  final int totalCount;  // 服务端分页总数
  final Set<String> selectedUuuids;
  final String? selectedExpenseUuid;
  final bool isPrivacyHidden;
  final String? currentStatusFilter;
  final TextEditingController searchController;

  final ValueChanged<String> onSelectRowChanged;
  final ValueChanged<Set<String>> onMultiSelectChanged;
  final void Function(String uuuid, String nextStatus) onUpdateStatus;
  final void Function(Set<String> uuuids, String nextStatus) onBatchUpdateStatus;
  final ValueChanged<String> onBlockExpense;
  final ValueChanged<String> onUnblockExpense;
  final ValueChanged<String> onDeleteExpense;
  final VoidCallback onAddExpenseSubmitted;
  final ValueChanged<String?> onStatusFilterChanged;
  final VoidCallback onSearchChanged;
  final ValueChanged<int> onPageChanged;  // 新的 skip 值
  final List<String> cachedProjects;      // 父级缓存的项目列表
  final List<String> cachedTypes;         // 父级缓存的类型列表

  const ExpenseTablePanel({
    super.key,
    required this.expenses,
    required this.totalCount,
    required this.selectedUuuids,
    required this.selectedExpenseUuid,
    required this.isPrivacyHidden,
    required this.currentStatusFilter,
    required this.searchController,
    required this.onSelectRowChanged,
    required this.onMultiSelectChanged,
    required this.onUpdateStatus,
    required this.onBatchUpdateStatus,
    required this.onBlockExpense,
    required this.onUnblockExpense,
    required this.onDeleteExpense,
    required this.onAddExpenseSubmitted,
    required this.onStatusFilterChanged,
    required this.onSearchChanged,
    required this.onPageChanged,
    required this.cachedProjects,
    required this.cachedTypes,
  });

  @override
  State<ExpenseTablePanel> createState() => _ExpenseTablePanelState();
}

class _ExpenseTablePanelState extends State<ExpenseTablePanel>
    with ColumnWidthManager {
  // ── 服务端分页 ──
  int _currentPage = 0;
  static const int _pageSize = 50;
  bool _searchVisible = false;

  // ── 选中金额缓存 ──
  double _cachedSelectedTotal = 0.0;
  // ── 全选状态缓存（避免 build 中 O(n) 遍历）──
  bool? _cachedAllPageSelected = false;

  // ── 内联编辑状态 ──
  (String, int)? _editingCell;       // (uuuid, colIndex) — 当前正在编辑的单元格
  TextEditingController? _editCtrl;  // 文本类编辑的控制器
  FocusNode? _editFocus;             // 文本类编辑的焦点

  int get _totalPages =>
      widget.totalCount == 0 ? 0 : (widget.totalCount / _pageSize).ceil();

  List<dynamic> get _pagedExpenses => widget.expenses;

  /// 当前页是否全部选中（null = 部分选中）— 结果缓存，数据变更时刷新
  bool? get _isAllPageSelected => _cachedAllPageSelected;

  void _recomputeAllPageSelected() {
    final page = widget.expenses;
    if (page.isEmpty) {
      _cachedAllPageSelected = false;
      return;
    }
    int selectedCount = 0;
    for (final e in page) {
      if (widget.selectedUuuids.contains(e['uuuid']?.toString())) {
        selectedCount++;
      }
    }
    if (selectedCount == 0) {
      _cachedAllPageSelected = false;
    } else if (selectedCount == page.length) {
      _cachedAllPageSelected = true;
    } else {
      _cachedAllPageSelected = null; // 部分选中
    }
  }

  void _toggleSelectAllPage() {
    final page = widget.expenses;
    if (page.isEmpty) return;
    final updated = Set<String>.from(widget.selectedUuuids);
    if (_isAllPageSelected == true) {
      // 当前页全选 → 取消当前页所有勾选
      for (final e in page) {
        updated.remove(e['uuuid']?.toString());
      }
    } else {
      // 未全选 / 部分选中 → 勾选当前页全部
      for (final e in page) {
        updated.add(e['uuuid']?.toString() ?? '');
      }
    }
    widget.onMultiSelectChanged(updated);
  }

  List<String> get _existingProjects => widget.cachedProjects;

  List<String> get _existingTypes => widget.cachedTypes;

  @override
  void initState() {
    super.initState();
    loadColumnWidths();
    _recomputeSelectedTotal();
    _recomputeAllPageSelected();  // 首次加载时计算缓存
  }

  @override
  void didUpdateWidget(covariant ExpenseTablePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据变更时重新计算选中金额缓存和全选状态
    if (oldWidget.selectedUuuids != widget.selectedUuuids ||
        oldWidget.expenses != widget.expenses) {
      _recomputeSelectedTotal();
      _recomputeAllPageSelected();
    }
    // 数据源变更（搜索/筛选/日期范围变化）→ 重置到第一页
    if (oldWidget.expenses != widget.expenses && _currentPage > 0) {
      _currentPage = 0;
    }
  }

  void _recomputeSelectedTotal() {
    double total = 0;
    for (final e in widget.expenses) {
      if (widget.selectedUuuids.contains(e['uuuid']?.toString())) {
        total += (e['amount'] as num?)?.toDouble() ?? 0;
      }
    }
    _cachedSelectedTotal = total;
  }

  @override
  void dispose() {
    _editCtrl?.dispose();
    _editFocus?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🏗️ build
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _buildToolbar(),
          const Divider(height: 1),
          Expanded(child: _buildTable()),
          if (_totalPages > 1) _buildPagination(),
          if (widget.selectedUuuids.isNotEmpty) _buildSelectionFooter(),
        ],
      ),
    );
  }

  // ── 工具栏 ──
  Widget _buildToolbar() {
    final selectedItems = widget.expenses
        .where((e) => widget.selectedUuuids.contains(e['uuuid']?.toString()))
        .toList();
    final allBlocked = selectedItems.isNotEmpty &&
        selectedItems.every((e) => e['status'] == '已屏蔽');
    final hasNormal = selectedItems.any((e) => e['status'] != '已屏蔽');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Row(children: [
                const Text('明细',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                _buildSearch(),
                const SizedBox(width: 8),
                _statusFilter(),
                const Spacer(),
                if (allBlocked) ...[
                  _actionBtn('恢复', Icons.lock_open, Colors.orange,
                      () => _batchUnblock()),
                  const SizedBox(width: 4),
                  _batchDeleteBtn(),
                  const SizedBox(width: 4),
                ],
                if (hasNormal)
                  _actionBtn('屏蔽', Icons.block, Colors.orange.shade700,
                      () => _batchBlock()),
                if (widget.selectedUuuids.isNotEmpty) ...[
                  if (hasNormal) const SizedBox(width: 4),
                  _batchStatusMenu(),
                  const SizedBox(width: 4),
                  _exportBtn(),
                ],
                const SizedBox(width: 4),
                _addBtn(),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── 状态批量菜单 ──
  static const _batchStatusItems = [
    ('待开票', Colors.orange),
    ('已开票', Colors.green),
    ('待报销', Colors.amber),
    ('核销中', Colors.blue),
    ('已完结', Colors.purple),
  ];

  Widget _batchStatusMenu() {
    return PopupMenuButton<String>(
      offset: const Offset(0, 34),
      tooltip: '批量更改状态',
      onSelected: (next) =>
          widget.onBatchUpdateStatus(widget.selectedUuuids, next),
      itemBuilder: (_) => _batchStatusItems.map((e) {
        return PopupMenuItem<String>(
          value: e.$1,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: e.$2, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(e.$1, style: const TextStyle(fontSize: 12)),
          ]),
        );
      }).toList(),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF4F46E5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sync, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text('批量 (${widget.selectedUuuids.length})',
              style: const TextStyle(fontSize: 12, color: Colors.white)),
          const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
        ]),
      ),
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
    );
  }

  Widget _buildSearch() {
    if (!_searchVisible) {
      return IconButton(
        icon: const Icon(Icons.search, size: 18),
        tooltip: '搜索',
        onPressed: () => setState(() => _searchVisible = true),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );
    }
    return SizedBox(
      width: 160,
      height: 34,
      child: TextField(
        controller: widget.searchController,
        autofocus: true,
        style: const TextStyle(fontSize: 12),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: '搜索...',
          hintStyle: const TextStyle(fontSize: 12),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, size: 14),
            onPressed: () {
              widget.searchController.clear();
              widget.onSearchChanged();
              setState(() => _searchVisible = false);
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
        ),
        onChanged: (_) => widget.onSearchChanged(),
        onSubmitted: (_) => widget.onSearchChanged(),
      ),
    );
  }

  Widget _statusFilter() {
    final current = widget.currentStatusFilter ?? '全部';
    final currentColor = _statusColors[current] ?? Colors.grey;
    const allLabels = [
      '全部', '待开票', '已开票', '待报销', '核销中', '已完结', '已屏蔽'
    ];
    return PopupMenuButton<String>(
      offset: const Offset(0, 34),
      tooltip: '状态筛选',
      onSelected: (v) => widget.onStatusFilterChanged(v == '全部' ? null : v),
      itemBuilder: (_) => allLabels.map((s) {
        final clr = _statusColors[s] ?? Colors.grey;
        final isCurrent = s == current;
        return PopupMenuItem<String>(
          value: s,
          enabled: !isCurrent,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: clr, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(s,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? clr : Colors.black87)),
            if (isCurrent) ...[
              const SizedBox(width: 6),
              Icon(Icons.check, size: 14, color: clr),
            ],
          ]),
        );
      }).toList(),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF4F46E5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: currentColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(current,
              style: const TextStyle(fontSize: 12, color: Colors.white)),
          const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
        ]),
      ),
    );
  }

  void _batchBlock() async {
    final blockedUuids = widget.expenses
        .where((e) => e['status'] == '已屏蔽')
        .map((e) => e['uuuid']?.toString())
        .toSet();
    final toBlock = widget.selectedUuuids
        .where((id) => !blockedUuids.contains(id))
        .toList();
    int success = 0;
    await Future.wait(
      toBlock.map((id) => ExpenseService.blockExpense(id).then((_) {
            success++;
          }, onError: (_) {})),
    );
    if (mounted) {
      _showSnack('屏蔽完成: $success / ${toBlock.length} 条');
      widget.onAddExpenseSubmitted();
    }
  }

  void _batchUnblock() async {
    int success = 0;
    final ids = widget.selectedUuuids.toList();
    await Future.wait(
      ids.map((id) => ExpenseService.unblockExpense(id).then((_) {
            success++;
          }, onError: (_) {})),
    );
    if (mounted) {
      _showSnack('恢复完成: $success / ${ids.length} 条');
      widget.onAddExpenseSubmitted();
    }
  }

  Widget _batchDeleteBtn() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: const Icon(Icons.delete_outline, size: 16),
      label: const Text('删除', style: TextStyle(fontSize: 12)),
      onPressed: () => _showBatchDeleteConfirmation(),
    );
  }

  void _showBatchDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
          SizedBox(width: 8),
          Text('确认批量删除？'),
        ]),
        content: Text(
            '你确定要删除选中的 ${widget.selectedUuuids.length} 条记录吗？此操作不可逆！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('取消', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(ctx).pop();
              int success = 0;
              final ids = widget.selectedUuuids.toList();
              await Future.wait(
                ids.map((id) => ExpenseService.deleteExpense(id).then((_) {
                      success++;
                    }, onError: (_) {})),
              );
              if (mounted) {
                _showSnack('删除完成: $success / ${ids.length} 条');
                widget.onMultiSelectChanged({});  // 清空选中状态 → 连锁清空 PDF 面板
                widget.onAddExpenseSubmitted();
              }
            },
            child:
                const Text('确认删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _addBtn() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('新增', style: TextStyle(fontSize: 12)),
      onPressed: _showAddExpenseDialog,
    );
  }

  // ── 导出 PDF ──
  Widget _exportBtn() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF059669),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: const Icon(Icons.file_download, size: 16),
      label: const Text('导出', style: TextStyle(fontSize: 12)),
      onPressed: _onExportPdfs,
    );
  }

  Future<void> _onExportPdfs() async {
    // 弹出文件夹选择器
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (dir == null || !mounted) return; // 用户取消

    try {
      final result = await ExpenseService.exportPdfs(widget.selectedUuuids, dir);
      final allCount = result['all_count'] as int? ?? 0;
      final vatCount = result['vat_count'] as int? ?? 0;
      final exportDir = result['export_dir']?.toString() ?? dir;
      if (mounted) {
        _showSnack('导出完成：全部 $allCount 个 PDF（含 $vatCount 张增值票）已保存到 $exportDir');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('导出失败: $e', isError: true);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // ✏️ 内联编辑
  // ═══════════════════════════════════════════════════════════════════

  /// 列索引 → API 字段名
  static String _colFieldName(int colIndex) {
    const map = {
      0: 'invoice_type',
      1: 'incurred_date',
      2: 'title',
      3: 'amount',
      5: 'project_name',
      6: 'expense_type',
      7: 'remark',
    };
    return map[colIndex] ?? '';
  }

  /// 进入文本编辑模式
  void _startTextEdit(String uuuid, int colIndex, String initialValue) {
    _editCtrl?.dispose();
    _editFocus?.dispose();
    _editCtrl = TextEditingController(text: initialValue);
    _editFocus = FocusNode();
    setState(() => _editingCell = (uuuid, colIndex));
    // 下一帧请求焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocus?.requestFocus();
    });
  }

  /// 提交文本编辑 → 调用 API → 退出编辑
  Future<void> _commitTextEdit() async {
    final cell = _editingCell;
    if (cell == null || _editCtrl == null) return;
    final (uuuid, colIndex) = cell;
    final field = _colFieldName(colIndex);
    final rawValue = _editCtrl!.text.trim();
    if (field.isEmpty || rawValue.isEmpty) {
      _cancelEdit();
      return;
    }
    try {
      dynamic value = rawValue;
      if (field == 'amount') {
        value = double.tryParse(rawValue);
        if (value == null) { _cancelEdit(); return; }
      }
      await ExpenseService.updateExpense(uuuid, {field: value});
      _cancelEdit();
      widget.onAddExpenseSubmitted();
    } catch (e) {
      _cancelEdit();
      _showSnack('保存失败: $e', isError: true);
    }
  }

  /// 提交特殊编辑（发票类型/日期） → 调用 API → 退出编辑
  Future<void> _commitSpecialEdit(String uuuid, int colIndex, dynamic value) async {
    final field = _colFieldName(colIndex);
    if (field.isEmpty) return;
    try {
      await ExpenseService.updateExpense(uuuid, {field: value});
      _cancelEdit();
      widget.onAddExpenseSubmitted();
    } catch (e) {
      _cancelEdit();
      _showSnack('保存失败: $e', isError: true);
    }
  }

  /// 取消编辑
  void _cancelEdit() {
    _editCtrl?.dispose();
    _editCtrl = null;
    _editFocus?.dispose();
    _editFocus = null;
    setState(() => _editingCell = null);
  }

  /// 判断某个单元格是否处于编辑态
  bool _isEditing(String uuuid, int colIndex) =>
      _editingCell != null &&
      _editingCell!.$1 == uuuid &&
      _editingCell!.$2 == colIndex;

  // ── 内联编辑单元格构建器 ──

  /// 发票类型列 (col 0) — 双击弹出选择菜单
  Widget _buildInvoiceTypeCell(double width, String uuuid, String invoiceType) {
    return GestureDetector(
      onDoubleTap: () => _showInvoiceTypePicker(uuuid, invoiceType),
      child: _cellWidget(width, _invoiceTypeIcon(invoiceType)),
    );
  }

  void _showInvoiceTypePicker(String uuuid, String current) {
    showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 300, 201, 301), // 大致居中
      items: ['普票', '增值票', '备注'].map((t) {
        final isCurrent = t == current;
        return PopupMenuItem<String>(
          value: t,
          enabled: !isCurrent,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isCurrent) const Icon(Icons.check, size: 14),
            if (isCurrent) const SizedBox(width: 6),
            Text(t, style: TextStyle(fontSize: 12,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
          ]),
        );
      }).toList(),
    ).then((v) {
      if (v != null && v != current) {
        _commitSpecialEdit(uuuid, 0, v);
      }
    });
  }

  /// 日期列 (col 1) — 双击弹出日期选择器
  Widget _buildDateCell(double width, String uuuid, String dateStr) {
    return GestureDetector(
      onDoubleTap: () => _showDatePickerForCell(uuuid, dateStr),
      child: _cellWidget(width, Text(dateStr,
          textAlign: TextAlign.center,
          style: _cellBaseStyle.copyWith(color: const Color(0xFF334155)))),
    );
  }

  Future<void> _showDatePickerForCell(String uuuid, String dateStr) async {
    DateTime initial;
    try {
      initial = DateTime.parse(dateStr);
    } catch (_) {
      initial = DateTime.now();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      final newDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      await _commitSpecialEdit(uuuid, 1, newDate);
    }
  }

  /// 通用文本编辑列 (cols 2/3/7) — 双击变为 TextField
  Widget _buildTextEditCell(double width, String uuuid, int colIndex, String displayValue,
      {bool isNumeric = false, bool monospace = false, bool bold = false, Color color = const Color(0xFF334155), String? editValue}) {
    final editVal = editValue ?? displayValue;
    if (_isEditing(uuuid, colIndex)) {
      return SizedBox(
        width: width,
        child: TextField(
          controller: _editCtrl,
          focusNode: _editFocus,
          style: _cellBaseStyle.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            fontFamily: monospace ? 'Consolas' : null,
          ),
          textAlign: TextAlign.center,
          keyboardType: isNumeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Color(0xFF4F46E5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
            ),
          ),
          onSubmitted: (_) => _commitTextEdit(),
          onTapOutside: (_) => _commitTextEdit(),
        ),
      );
    }
    return GestureDetector(
      onDoubleTap: () => _startTextEdit(uuuid, colIndex, editVal),
      child: _cellWidget(width, Text(displayValue,
          textAlign: TextAlign.center,
          softWrap: true,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: _cellBaseStyle.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            fontFamily: monospace ? 'Consolas' : null,
          ))),
    );
  }

  /// 项目 / 类型列 (cols 5/6) — 双击变为 TextField + 下拉自动完成
  Widget _buildAutocompleteCell(double width, String uuuid, int colIndex, String currentValue,
      {required List<String> options, required Widget display}) {
    if (_isEditing(uuuid, colIndex)) {
      return SizedBox(
        width: width,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _editCtrl,
              focusNode: _editFocus,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: '输入或选择...',
                hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                ),
              ),
              onSubmitted: (_) => _commitTextEdit(),
              onTapOutside: (_) => _commitTextEdit(),
            ),
          ),
          if (options.isNotEmpty)
            PopupMenuButton<String>(
              offset: const Offset(0, 28),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              onSelected: (v) {
                _editCtrl?.text = v;
                _commitTextEdit();
              },
              itemBuilder: (_) => options.map((o) =>
                  PopupMenuItem<String>(value: o, child: Text(o, style: const TextStyle(fontSize: 12)))
              ).toList(),
            ),
        ]),
      );
    }
    return GestureDetector(
      onDoubleTap: () => _startTextEdit(uuuid, colIndex, currentValue == '-' ? '' : currentValue),
      child: _cellWidget(width, display),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📊 数据表格（可拖拽列宽）
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildTable() {
    final displayData = _pagedExpenses;
    if (displayData.isEmpty) {
      return const Center(
          child: Text('暂无匹配的开销记录流水',
              style: TextStyle(color: Colors.black54, fontSize: 14)));
    }

    return LayoutBuilder(builder: (ctx, constraints) {
      initColumnWidths(constraints.maxWidth);

      // 计算内容总宽度（checkbox 42 + 列宽和 + 8个8px间隔）
      final colsWidth = columnWidths.values.fold(0.0, (a, b) => a + b);
      final contentW = 42.0 + colsWidth + 64.0;

      return RepaintBoundary(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentW,
                    child: Column(
                      children: [
                      _buildResizableHeader(),
                      _buildDataRows(displayData),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );  // RepaintBoundary
  });
  }

  /// 可拖拽列头
  Widget _buildResizableHeader() {
    final colDefs = [
      ('发票', 0),
      ('日期', 1),
      ('事由', 2),
      ('金额', 3),
      ('状态', 4),
      ('项目', 5),
      ('类型', 6),
      ('备注', 7),
    ];

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // ── 全选复选框 ──
          SizedBox(
            width: 42,
            child: Checkbox(
              value: _isAllPageSelected,
              tristate: true,
              onChanged: (v) => _toggleSelectAllPage(),
            ),
          ),
          ...List.generate(colDefs.length, (i) {
            final (label, colIdx) = colDefs[i];
            final width = columnWidths[colIdx] ?? 100.0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: width,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF475569)),
                  ),
                ),
                // ── 拖拽手柄 ──
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) {
                    resizingColIndex = colIdx;
                    resizeStartX = 0;
                    resizeStartWidth = columnWidths[colIdx]!;
                  },
                  onPanUpdate: (d) {
                    if (resizingColIndex == null) return;
                    resizeStartX += d.delta.dx;
                    final newWidth =
                        (resizeStartWidth + resizeStartX).clamp(
                            ColumnWidthManager.minColWidth, 400.0);
                    setState(() {
                      columnWidths[resizingColIndex!] = newWidth;
                    });
                  },
                  onPanEnd: (_) {
                    resizingColIndex = null;
                    saveColumnWidths();
                  },
                  child: Container(
                    width: 8,
                    height: 24,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 2,
                        height: 16,
                        decoration: BoxDecoration(
                          color: resizingColIndex == colIdx
                              ? Colors.blue
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// 数据行（自定义布局，不走 DataTable）
  Widget _buildDataRows(List<dynamic> displayData) {
    return Column(
      children: displayData.map((expense) {
        final uuuid = expense['uuuid']?.toString() ?? '';
        final date = expense['incurred_date']?.toString() ?? '-';
        final project = expense['project_name']?.toString() ?? '-';
        final type = expense['expense_type']?.toString() ?? '-';
        final title = expense['title']?.toString() ?? '无事由';
        final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
        final status = expense['status']?.toString() ?? '待开票';
        final invoiceType = expense['invoice_type']?.toString() ?? '备注';
        final remark = expense['remark']?.toString() ?? '';
        final isChecked = widget.selectedUuuids.contains(uuuid);
        final isSelected = widget.selectedExpenseUuid == uuuid;
        final statusClr = _statusColor(status);

        return InkWell(
          onTap: () {
            widget.onSelectRowChanged(uuuid);
            widget.onMultiSelectChanged({uuuid});
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEEF2FF)
                  : isChecked
                      ? const Color(0xFFF0F4FF)
                      : null,
              border: Border(
                  bottom:
                      BorderSide(color: Colors.grey.shade200, width: 0.5)),
            ),
            child: Row(children: [
              // ── 复选框 ──
              SizedBox(
                width: 42,
                child: Checkbox(
                  value: isChecked,
                  onChanged: (v) {
                    final updated = Set<String>.from(widget.selectedUuuids);
                    if (v == true) {
                      updated.add(uuuid);
                      widget.onMultiSelectChanged(updated);
                      widget.onSelectRowChanged(uuuid);
                    } else {
                      updated.remove(uuuid);
                      widget.onMultiSelectChanged(updated);
                    }
                  },
                ),
              ),
              // ── 列数据（每个 cell 后紧跟 8px 占位，匹配表头手柄宽度） ──
              // 0: 发票类型 — 双击弹出选择
              _buildInvoiceTypeCell(columnWidths[0] ?? 50, uuuid, invoiceType),
              const SizedBox(width: 8),
              // 1: 日期 — 双击弹出日期选择器
              _buildDateCell(columnWidths[1] ?? 100, uuuid, date),
              const SizedBox(width: 8),
              // 2: 事由 — 双击文本编辑
              _buildTextEditCell(columnWidths[2] ?? 150, uuuid, 2, title,
                  color: const Color(0xFF64748B)),
              const SizedBox(width: 8),
              // 3: 金额 — 双击数字编辑（隐私模式下仍传递真实值）
              _buildTextEditCell(columnWidths[3] ?? 80, uuuid, 3,
                  widget.isPrivacyHidden ? '****' : amount.toStringAsFixed(2),
                  isNumeric: true, monospace: true, bold: true,
                  color: const Color(0xFF0F172A),
                  editValue: amount.toStringAsFixed(2)),
              const SizedBox(width: 8),
              // 4: 状态 — 单击下拉（保持原有交互）
              _cellWidget(
                  columnWidths[4] ?? 100,
                  _statusDropdown(uuuid, status, statusClr)),
              const SizedBox(width: 8),
              // 5: 项目 — 双击编辑 + 下拉自动完成
              _buildAutocompleteCell(columnWidths[5] ?? 100, uuuid, 5, project,
                  options: _existingProjects,
                  display: project == '-' ? Text('-', style: _cellStyle()) : _tag(project, bg: const Color(0xFFE0F2FE), fg: const Color(0xFF0284C7))),
              const SizedBox(width: 8),
              // 6: 类型 — 双击编辑 + 下拉自动完成
              _buildAutocompleteCell(columnWidths[6] ?? 100, uuuid, 6, type,
                  options: _existingTypes,
                  display: _typeTag(type)),
              const SizedBox(width: 8),
              // 7: 备注 — 双击文本编辑
              _buildTextEditCell(columnWidths[7] ?? 120, uuuid, 7, remark,
                  color: const Color(0xFF64748B)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  /// 通用文本单元格 — 居中、支持换行

  Widget _cellWidget(double width, Widget child) {
    return SizedBox(
      width: width,
      child: Center(child: child),
    );
  }

  TextStyle _cellStyle() => const TextStyle(fontSize: 12);

  static const _cellBaseStyle = TextStyle(fontSize: 12);

  Widget _tag(String text,
      {Color bg = const Color(0xFFF1F5F9),
      Color fg = const Color(0xFF475569)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  /// 发票类型图标
  Widget _invoiceTypeIcon(String invoiceType) {
    IconData icon;
    Color color;
    String tooltip;
    switch (invoiceType) {
      case '普票':
        icon = Icons.receipt;
        color = Colors.green;
        tooltip = '普通发票';
        break;
      case '增值票':
        icon = Icons.verified;
        color = Colors.blue;
        tooltip = '增值税专用发票';
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
        tooltip = '未识别 / 备注';
    }
    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 20, color: color),
    );
  }

  // ── 类型标签 ──
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(type,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔽 状态下拉
  // ═══════════════════════════════════════════════════════════════════
  static const _statusColors = {
    '待开票': Colors.orange,
    '已开票': Colors.green,
    '待报销': Color(0xFFD97706),
    '核销中': Colors.blue,
    '已完结': Colors.purple,
    '已屏蔽': Colors.redAccent,
  };

  Widget _statusDropdown(String uuuid, String status, Color color) {
    const allStatuses = ['待开票', '已开票', '待报销', '核销中', '已完结'];
    return GestureDetector(
      onTapDown: (details) {
        showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy + 32,
            details.globalPosition.dx + 1,
            details.globalPosition.dy,
          ),
          items: allStatuses.map((name) {
            final c = _statusColors[name] ?? Colors.grey;
            final isCurrent = name == status;
            return PopupMenuItem<String>(
              value: name,
              enabled: !isCurrent,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(name,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? c : Colors.black87)),
                if (isCurrent) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check, size: 14, color: c),
                ],
              ]),
            );
          }).toList(),
        ).then((next) {
          if (next != null) widget.onUpdateStatus(uuuid, next);
        });
      },
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(status,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 14, color: color),
        ]),
      ),
      ),
    );
  }

  Color _statusColor(String status) {
    return _statusColors[status] ?? Colors.grey;
  }

  // ── 服务端分页 ──
  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed:
                _currentPage > 0 ? () {
                  setState(() => _currentPage--);
                  widget.onPageChanged(_currentPage * _pageSize);
                } : null,
            tooltip: '上一页',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '第 ${_currentPage + 1} / $_totalPages 页  (共 ${widget.totalCount} 条)',
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: _currentPage < _totalPages - 1
                ? () {
                    setState(() => _currentPage++);
                    widget.onPageChanged(_currentPage * _pageSize);
                  }
                : null,
            tooltip: '下一页',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ➕ 新增开销 Dialog
  // ═══════════════════════════════════════════════════════════════════
  void _showAddExpenseDialog() {
    showDialog(
      context: context,
      builder: (_) => AddExpenseDialog(
        existingProjects: _existingProjects,
        existingTypes: _existingTypes,
        onSubmitted: widget.onAddExpenseSubmitted,
      ),
    );
  }

  // ── 选中金额汇总底栏（缓存计算，仅在多选变更时更新） ──
  Widget _buildSelectionFooter() {
    final lower = _cachedSelectedTotal.toStringAsFixed(2);
    final upper = toChineseUppercase(_cachedSelectedTotal);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4).withValues(alpha: 0.9),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Text('已选 ${widget.selectedUuuids.length} 条',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF475569))),
          const Spacer(),
          const Text('合计：',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF475569))),
          Text('¥$lower',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF059669),
                  fontFamily: 'Consolas')),
          const SizedBox(width: 16),
          Text(upper,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF065F46))),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}


// ═══════════════════════════════════════════════════════════════════
// 🔢 人民币大写转换
// ═══════════════════════════════════════════════════════════════════

/// 缓存最近的大写转换结果，避免重复计算
final Map<double, String> _uppercaseCache = {};

/// 将金额转换为中文财务大写（如 12345.67 → 壹万贰仟叁佰肆拾伍元陆角柒分）
String toChineseUppercase(double amount) {
  // 优先命中缓存（常见金额如每月固定开销重复出现）
  final cached = _uppercaseCache[amount];
  if (cached != null) return cached;

  if (amount < 0.005) return _cachePut(amount, '零元整');

  const digits = ['零', '壹', '贰', '叁', '肆', '伍', '陆', '柒', '捌', '玖'];
  const units = ['', '拾', '佰', '仟'];
  const bigUnits = ['', '万', '亿', '兆'];

  final numStr = amount.toStringAsFixed(2);
  final parts = numStr.split('.');
  final intStr = parts[0];
  final jiao = int.parse(parts[1][0]);
  final fen = int.parse(parts[1][1]);

  String result = '';

  // ── 整数部分：每 4 位一组（个/万/亿） ──
  if (intStr != '0') {
    final len = intStr.length;
    // 补齐到 4 的倍数方便分组
    final padLen = ((len + 3) ~/ 4) * 4;
    final padded = intStr.padLeft(padLen, '0');
    final groupCount = padLen ~/ 4;

    final groups = <String>[];
    for (int g = 0; g < groupCount; g++) {
      final start = g * 4;
      final seg = padded.substring(start, start + 4);
      final bigIdx = groupCount - 1 - g; // 当前组对应的 bigUnit 索引

      String segStr = '';
      bool hasNonZero = false;
      for (int i = 0; i < 4; i++) {
        final d = int.parse(seg[i]);
        if (d != 0) {
          // 跨组零：当组有前导零（第一个非零数字不在 seg 首位），且前面已有内容时补零
          if (i > 0 && !hasNonZero && groups.isNotEmpty) {
            segStr += '零';
          }
          segStr += digits[d] + units[3 - i];
          hasNonZero = true;
        } else {
          if (hasNonZero && !segStr.endsWith('零')) {
            segStr += '零';
          }
        }
      }
      // 去掉末尾的零
      while (segStr.endsWith('零')) {
        segStr = segStr.substring(0, segStr.length - 1);
      }
      if (segStr.isNotEmpty && bigIdx > 0) {
        segStr += bigUnits[bigIdx];
      }
      if (segStr.isNotEmpty) {
        groups.add(segStr);
      }
    }
    result = groups.join();
    // 清理连续零
    result = result.replaceAll(RegExp(r'零+'), '零');
    // 去掉末尾零（可能在大单位前）
    if (result.endsWith('零')) {
      result = result.substring(0, result.length - 1);
    }
    result += '元';
  }

  // ── 角分 ──
  if (jiao == 0 && fen == 0) {
    result += '整';
  } else {
    if (jiao > 0) result += '${digits[jiao]}角';
    if (fen > 0) result += '${digits[fen]}分';
  }

  return _cachePut(amount, result);
}

String _cachePut(double key, String value) {
  // LRU 简单策略：缓存最多 50 条
  if (_uppercaseCache.length >= 50) {
    _uppercaseCache.remove(_uppercaseCache.keys.first);
  }
  return _uppercaseCache[key] = value;
}
