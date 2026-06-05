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

class _ExpenseTablePanelState extends State<ExpenseTablePanel>
    with ColumnWidthManager {
  // ── 分页 ──
  int _currentPage = 0;
  static const int _pageSize = 50;
  bool _searchVisible = false;

  int get _totalPages =>
      widget.expenses.isEmpty ? 0 : (widget.expenses.length / _pageSize).ceil();

  List<dynamic> get _pagedExpenses {
    if (widget.expenses.isEmpty) return [];
    final start = _currentPage * _pageSize;
    final end = start + _pageSize;
    if (start >= widget.expenses.length) {
      _currentPage = _totalPages - 1;
      final newStart = _currentPage * _pageSize;
      return widget.expenses.sublist(
          newStart, (newStart + _pageSize).clamp(0, widget.expenses.length));
    }
    return widget.expenses.sublist(start, end.clamp(0, widget.expenses.length));
  }

  /// 当前页是否全部选中（null = 部分选中）
  bool? get _isAllPageSelected {
    final page = _pagedExpenses;
    if (page.isEmpty) return false;
    int selectedCount = 0;
    for (final e in page) {
      if (widget.selectedUuuids.contains(e['uuuid']?.toString())) {
        selectedCount++;
      }
    }
    if (selectedCount == 0) return false;
    if (selectedCount == page.length) return true;
    return null; // 部分选中
  }

  void _toggleSelectAllPage() {
    final page = _pagedExpenses;
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
  void initState() {
    super.initState();
    loadColumnWidths();
  }

  @override
  void dispose() {
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
            height: 52,
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
              _cellWidget(columnWidths[0] ?? 50, _invoiceTypeIcon(invoiceType)),
              const SizedBox(width: 8),
              _cell(columnWidths[1] ?? 100, date,
                  color: const Color(0xFF334155)),
              const SizedBox(width: 8),
              _cell(columnWidths[2] ?? 150, title,
                  color: const Color(0xFF64748B), bold: false),
              const SizedBox(width: 8),
              _cell(columnWidths[3] ?? 80,
                  widget.isPrivacyHidden ? '****' : amount.toStringAsFixed(2),
                  color: const Color(0xFF0F172A),
                  bold: true,
                  monospace: true),
              const SizedBox(width: 8),
              _cellWidget(
                  columnWidths[4] ?? 100,
                  _statusDropdown(uuuid, status, statusClr)),
              const SizedBox(width: 8),
              _cellWidget(columnWidths[5] ?? 100,
                  project == '-' ? Text('-', style: _cellStyle()) : _tag(project, bg: const Color(0xFFE0F2FE), fg: const Color(0xFF0284C7))),
              const SizedBox(width: 8),
              _cellWidget(columnWidths[6] ?? 100, _typeTag(type)),
              const SizedBox(width: 8),
              _cell(columnWidths[7] ?? 120, remark, color: const Color(0xFF64748B)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  /// 通用文本单元格 — 居中、支持换行
  Widget _cell(double width, String text,
      {Color color = const Color(0xFF334155),
      bool bold = false,
      bool monospace = false}) {
    return _cellWidget(
      width,
      Text(
        text,
        textAlign: TextAlign.center,
        softWrap: true,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          fontFamily: monospace ? 'Consolas' : null,
        ),
      ),
    );
  }

  Widget _cellWidget(double width, Widget child) {
    return SizedBox(
      width: width,
      child: Center(child: child),
    );
  }

  TextStyle _cellStyle() => const TextStyle(fontSize: 12);

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

  // ── 分页 ──
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
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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

  // ── 选中金额汇总底栏 ──
  Widget _buildSelectionFooter() {
    double total = 0;
    for (final e in widget.expenses) {
      if (widget.selectedUuuids.contains(e['uuuid']?.toString())) {
        total += (e['amount'] as num?)?.toDouble() ?? 0;
      }
    }
    final lower = total.toStringAsFixed(2);
    final upper = _toChineseUppercase(total);

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

/// 将金额转换为中文财务大写（如 12345.67 → 壹万贰仟叁佰肆拾伍元陆角柒分）
String _toChineseUppercase(double amount) {
  if (amount < 0.005) return '零元整';

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

  return result;
}
