import 'package:flutter/material.dart';
import '../../../services/expense_service.dart';
import '../../../widgets/glass_card.dart';

/// 业务流水表格面板 — 搜索 / 筛选 / 全选 / 状态流转 / 删除 / 新增
///
/// 包含 DataTable、工具栏（搜索框、状态筛选、删除按钮、新增按钮），
/// 以及「新增开销」Dialog（含项目/类型 Autocomplete）和「删除确认」Dialog。
/// 所有业务操作通过回调通知父级，自身不持有业务状态。
class ExpenseTablePanel extends StatefulWidget {
  // ── 数据输入 ──
  final List<dynamic> expenses;
  final Set<String> selectedUuuids;
  final String? selectedExpenseUuid;
  final bool isPrivacyHidden;
  final String? currentStatusFilter;
  final TextEditingController searchController;

  // ── 回调通知 ──
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

  const ExpenseTablePanel({
    super.key,
    required this.expenses,
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
  });

  @override
  State<ExpenseTablePanel> createState() => _ExpenseTablePanelState();
}

class _ExpenseTablePanelState extends State<ExpenseTablePanel> {
  // ── 新增表单控制器（仅本组件内部使用）──
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _projectCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();

  // ── 分页状态 ──
  int _currentPage = 0;
  static const int _pageSize = 50;

  // ── 搜索展开 ──
  bool _searchVisible = false;

  int get _totalPages =>
      widget.expenses.isEmpty ? 0 : (widget.expenses.length / _pageSize).ceil();

  List<dynamic> get _pagedExpenses {
    if (widget.expenses.isEmpty) return [];
    final start = _currentPage * _pageSize;
    final end = start + _pageSize;
    // 确保不超过列表长度
    if (start >= widget.expenses.length) {
      // 当前页超出范围（数据被删除），回退到最后一页
      _currentPage = _totalPages - 1;
      final newStart = _currentPage * _pageSize;
      return widget.expenses.sublist(
          newStart,
          (newStart + _pageSize).clamp(0, widget.expenses.length));
    }
    return widget.expenses.sublist(start, end.clamp(0, widget.expenses.length));
  }

  @override
  void didUpdateWidget(covariant ExpenseTablePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 不强制重置页码 — _pagedExpenses getter 会自动处理越界回退
  }

  // ── 从当前流水列表中提取去重后的 project / type 建议 ──
  List<String> get _existingProjects {
    return widget.expenses
        .map((e) => e['project_name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> get _existingTypes {
    return widget.expenses
        .map((e) => e['expense_type']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _dateCtrl.dispose();
    _projectCtrl.dispose();
    _typeCtrl.dispose();
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
        ],
      ),
    );
  }

  // ── 工具栏：标题 + 搜索 + 状态筛选 + 操作按钮 ──
  Widget _buildToolbar() {
    // 根据复选框选中的条目类型判断显示哪些操作按钮
    final selectedItems = widget.expenses
        .where((e) =>
            widget.selectedUuuids.contains(e['uuuid']?.toString()))
        .toList();
    final allBlocked = selectedItems.isNotEmpty &&
        selectedItems.every((e) => e['status'] == '已屏蔽');
    final hasNormal = selectedItems.any((e) => e['status'] != '已屏蔽');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Row(
                children: [
                  // ── 左侧：明细标题 + 搜索 + 状态筛选 ──
                  const Text('明细',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  _buildSearch(),
                  const SizedBox(width: 8),
                  _statusFilter(),
                  // ── 弹性空间，将右侧按钮组推到最右 ──
                  const Spacer(),
                  // ── 右侧：屏蔽/恢复/删除（批量左侧）+ 批量 + 新增（最右）──
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
                  ],
                  const SizedBox(width: 4),
                  _addBtn(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 批量状态修改 — 带颜色的下拉菜单（不含已屏蔽）
  Widget _batchStatusMenu() {
    const items = [
      ('待开票', Colors.orange),
      ('已开票', Colors.green),
      ('待报销', Colors.amber),
      ('核销中', Colors.blue),
      ('已完结', Colors.purple),
    ];
    return PopupMenuButton<String>(
      offset: const Offset(0, 34),
      tooltip: '批量更改状态',
      onSelected: (next) =>
          widget.onBatchUpdateStatus(widget.selectedUuuids, next),
      itemBuilder: (_) => items.map((e) {
        return PopupMenuItem<String>(
          value: e.$1,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: e.$2, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(e.$1, style: const TextStyle(fontSize: 12)),
          ]),
        );
      }).toList(),
      child: Container(
        height: 34,
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: const Color(0xFF4F46E5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sync, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text('批量 (${widget.selectedUuuids.length})',
              style:
                  const TextStyle(fontSize: 12, color: Colors.white)),
          const Icon(Icons.arrow_drop_down,
              size: 18, color: Colors.white),
        ]),
      ),
    );
  }

  /// 通用操作按钮（屏蔽/取消屏蔽）
  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
    );
  }

  /// 搜索：按钮形式，点击展开输入框
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

  /// 状态筛选 — PopupMenuButton 风格，与批量按钮 UI 一致
  Widget _statusFilter() {
    final current = widget.currentStatusFilter ?? '全部';
    final currentColor = _statusColors[current] ?? Colors.grey;
    const allLabels = [
      '全部', '待开票', '已开票', '待报销', '核销中', '已完结', '已屏蔽'
    ];

    return PopupMenuButton<String>(
      offset: const Offset(0, 34),
      tooltip: '状态筛选',
      onSelected: (v) =>
          widget.onStatusFilterChanged(v == '全部' ? null : v),
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
              decoration: BoxDecoration(
                  color: clr, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(s,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isCurrent ? FontWeight.bold : FontWeight.normal,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: const Color(0xFF4F46E5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: currentColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(current,
              style: const TextStyle(
                  fontSize: 12, color: Colors.white)),
          const Icon(Icons.arrow_drop_down,
              size: 18, color: Colors.white),
        ]),
      ),
    );
  }

  /// 批量屏蔽所有选中条目（跳过已屏蔽的，避免后端报错）
  void _batchBlock() {
    final blockedUuids = widget.expenses
        .where((e) => e['status'] == '已屏蔽')
        .map((e) => e['uuuid']?.toString())
        .toSet();
    for (final id in widget.selectedUuuids) {
      if (!blockedUuids.contains(id)) {
        widget.onBlockExpense(id);
      }
    }
  }

  /// 批量恢复所有选中条目
  void _batchUnblock() {
    for (final id in widget.selectedUuuids) {
      widget.onUnblockExpense(id);
    }
  }

  /// 批量删除按钮 + 确认
  Widget _batchDeleteBtn() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6)),
      ),
      icon: const Icon(Icons.delete_outline, size: 16),
      label: const Text('删除',
          style: const TextStyle(fontSize: 12)),
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
        content: Text('你确定要删除选中的 ${widget.selectedUuuids.length} 条记录吗？此操作不可逆！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              for (final id in widget.selectedUuuids) {
                widget.onDeleteExpense(id);
              }
            },
            child: const Text('确认删除', style: TextStyle(color: Colors.white)),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6)),
      ),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('新增', style: TextStyle(fontSize: 12)),
      onPressed: _showAddExpenseDialog,
    );
  }

  // ── 数据表格 ──
  Widget _buildTable() {
    final displayData = _pagedExpenses;
    if (displayData.isEmpty) {
      return const Center(
          child: Text('暂无匹配的开销记录流水',
              style: TextStyle(color: Colors.black54, fontSize: 14)));
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        // 计算自适应列间距：可用宽度减去固定列宽后均分
        final totalWidth = constraints.maxWidth;
        final spacing = (totalWidth > 600) ? ((totalWidth - 500) / 5).clamp(20.0, 60.0) : 20.0;
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: totalWidth),
              child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 52,
          columnSpacing: spacing,
          showCheckboxColumn: true,
          onSelectAll: (bool? selected) {
            if (selected == true) {
              widget.onMultiSelectChanged(
                  widget.expenses.map((e) => e['uuuid'].toString()).toSet());
            } else {
              widget.onMultiSelectChanged({});
            }
          },
          columns: const [
            DataColumn(
                label: Row(children: [
              SizedBox(width: 11),
              Text('发生日期',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 13))
            ])),
            DataColumn(
                label: Text('开销项目',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(
                label: Text('开销类型',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(
                label: Text('开销事由',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(
                numeric: true,
                label: Text('金额 (¥)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(
                label: Text('状态',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
          ],
          rows: displayData.map((expense) {
            final uuuid = expense['uuuid']?.toString() ?? '';
            final date = expense['incurred_date']?.toString() ?? '-';
            final project = expense['project_name']?.toString() ?? '-';
            final type = expense['expense_type']?.toString() ?? '-';
            final title = expense['title']?.toString() ?? '无事由';
            final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
            final status = expense['status']?.toString() ?? '待开票';
            final isChecked = widget.selectedUuuids.contains(uuuid);
            final isActive = uuuid == widget.selectedExpenseUuid;
            final statusClr = _statusColor(status);

            return DataRow(
              selected: isChecked,
              onSelectChanged: (bool? selected) {
                final updated = Set<String>.from(widget.selectedUuuids);
                if (selected == true) {
                  updated.add(uuuid);
                } else {
                  updated.remove(uuuid);
                }
                widget.onMultiSelectChanged(updated);
                // 同时切换右侧 PDF 预览
                widget.onSelectRowChanged(uuuid);
              },
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFFEEF2FF);
                }
                if (states.contains(WidgetState.hovered)) {
                  return Colors.white.withValues(alpha: 0.8);
                }
                return null;
              }),
              cells: [
                DataCell(Row(children: [
                  Container(
                    width: 3,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isChecked
                          ? const Color(0xFF4F46E5)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(2)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(date,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF334155)))),
                ])),
                DataCell(Text(project,
                    style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF334155),
                        fontWeight: project != '-'
                            ? FontWeight.w600
                            : FontWeight.normal))),
                DataCell(_typeTag(type)),
                DataCell(Text(title,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF64748B)),
                    overflow: TextOverflow.ellipsis)),
                DataCell(Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                        widget.isPrivacyHidden
                            ? '****'
                            : amount.toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'Consolas',
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A))))),
                DataCell(_statusDropdown(uuuid, status, statusClr)),
              ],
            );
          }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── 分页控件 ──
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
                _currentPage > 0 ? () => setState(() => _currentPage--) : null,
            tooltip: '上一页',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '第 ${_currentPage + 1} / $_totalPages 页  (共 ${widget.expenses.length} 条)',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: _currentPage < _totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
            tooltip: '下一页',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🏷️ 类型标签
  // ═══════════════════════════════════════════════════════════════════
  Widget _typeTag(String type) {
    Color bg; Color fg;
    switch (type) {
      case '差旅交通': bg = const Color(0xFFE0F2FE); fg = const Color(0xFF0284C7); break;
      case '云服务采购': bg = const Color(0xFFD1FAE5); fg = const Color(0xFF059669); break;
      case '招待': bg = const Color(0xFFFEF3C7); fg = const Color(0xFFD97706); break;
      default: bg = const Color(0xFFF1F5F9); fg = const Color(0xFF475569);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(type, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔽 状态下拉菜单（自由选择，不含已屏蔽，当前状态显示在菜单内，统一颜色UI）
  // ═══════════════════════════════════════════════════════════════════
  static const _statusColors = {
    '待开票': Colors.orange,
    '已开票': Colors.green,
    '待报销': Color(0xFFD97706), // amber.shade700
    '核销中': Colors.blue,
    '已完结': Colors.purple,
    '已屏蔽': Colors.redAccent,
  };

  Widget _statusDropdown(String uuuid, String status, Color color) {
    const allStatuses = ['待开票', '已开票', '待报销', '核销中', '已完结'];

    return PopupMenuButton<String>(
      offset: const Offset(0, 32),
      padding: EdgeInsets.zero,
      tooltip: '更改状态',
      onSelected: (next) => widget.onUpdateStatus(uuuid, next),
      itemBuilder: (_) => allStatuses.map((name) {
        final c = _statusColors[name] ?? Colors.grey;
        final isCurrent = name == status;
        return PopupMenuItem<String>(
          value: name,
          enabled: !isCurrent,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(name,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? c : Colors.black87)),
            if (isCurrent) ...[
              const SizedBox(width: 6),
              Icon(Icons.check, size: 14, color: c),
            ],
          ]),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(status,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 14, color: color),
        ]),
      ),
    );
  }

  Color _statusColor(String status) {
    return _statusColors[status] ?? Colors.grey;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ➕ 新增开销 Dialog
  // ═══════════════════════════════════════════════════════════════════
  void _showAddExpenseDialog() {
    _clearForm();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white.withValues(alpha: 0.95),
            title: const Text('新增业务开销记录',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field('事由 / 开销名称 *', Icons.edit_note, _titleCtrl,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '请输入事由' : null),
                    const SizedBox(height: 14),
                    _field(
                      '金额 (元) *',
                      Icons.attach_money,
                      _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '请输入金额';
                        if (double.tryParse(v.trim()) == null) return '请输入合法数字';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _dateCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: '发生日期 *',
                          prefixIcon: Icon(Icons.calendar_today)),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null) {
                          _dateCtrl.text =
                              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                        }
                      },
                      validator: (v) =>
                          (v == null || v.isEmpty) ? '请选择日期' : null,
                    ),
                    const SizedBox(height: 14),
                    _autocompleteField(
                        '开销项目', Icons.folder_outlined, _projectCtrl,
                        options: _existingProjects),
                    const SizedBox(height: 14),
                    _autocompleteField(
                        '开销类型', Icons.category_outlined, _typeCtrl,
                        options: _existingTypes,
                        hint: '选择或输入类型（如差旅交通）'),
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
                onPressed: () => _submitAddExpense(ctx),
                child: const Text('提交保存',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _field(String label, IconData icon, TextEditingController ctrl,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
          labelText: label, prefixIcon: Icon(icon)),
      validator: validator,
    );
  }

  Widget _autocompleteField(
      String label, IconData icon, TextEditingController ctrl,
      {required List<String> options, String? hint}) {
    return Autocomplete<String>(
      optionsBuilder: (v) {
        if (v.text.isEmpty) return options;
        return options
            .where((o) => o.toLowerCase().contains(v.text.toLowerCase()));
      },
      onSelected: (val) => ctrl.text = val,
      fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
        controller.text = ctrl.text;
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (v) => ctrl.text = v,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            hintText: hint,
          ),
        );
      },
    );
  }

  Future<void> _submitAddExpense(BuildContext dialogCtx) async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await ExpenseService.addExpense({
        'title': _titleCtrl.text.trim(),
        'amount': double.parse(_amountCtrl.text.trim()),
        'incurred_date': _dateCtrl.text.trim(),
        'status': '待开票',
        'project_name':
            _projectCtrl.text.trim().isEmpty ? null : _projectCtrl.text.trim(),
        'expense_type':
            _typeCtrl.text.trim().isEmpty ? null : _typeCtrl.text.trim(),
      });
      _clearForm();
      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
      widget.onAddExpenseSubmitted();
    } catch (e) {
      _showSnack('新增失败: $e', isError: true);
    }
  }

  void _clearForm() {
    _titleCtrl.clear();
    _amountCtrl.clear();
    _dateCtrl.clear();
    _projectCtrl.clear();
    _typeCtrl.clear();
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
