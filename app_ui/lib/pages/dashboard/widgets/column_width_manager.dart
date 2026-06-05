import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../services/config_storage.dart';

/// 列宽持久化管理 mixin
///
/// 混入到 `State<ExpenseTablePanel>` 中使用，提供列宽的初始化、加载、
/// 保存功能，以及拖拽状态变量。
mixin ColumnWidthManager<T extends StatefulWidget> on State<T> {
  // ── 持久化 key ──
  static const _colWidthsKey = 'table_column_widths';
  bool _loadedSavedWidths = false;

  // ── 列宽状态 ──
  Map<int, double> columnWidths = {};
  static const double minColWidth = 60.0;
  int? resizingColIndex;
  double resizeStartX = 0;
  double resizeStartWidth = 0;

  double _lastTotalWidth = 0;

  bool get loadedSavedWidths => _loadedSavedWidths;

  /// 按比例分配列宽，确保总和精确 ≤ totalWidth，永不溢出。
  /// 若有已保存的列宽则直接复用，不重新计算比例。
  void initColumnWidths(double totalWidth) {
    if (_loadedSavedWidths) return;
    if ((totalWidth - _lastTotalWidth).abs() < 10) return; // 防抖 10px
    _lastTotalWidth = totalWidth;

    // 固定开销：col[0] 50 + checkbox 42 + 8个8px间隔 64 = 156
    const fixed = 50.0 + 42.0 + 64.0;
    final remaining = (totalWidth - fixed).clamp(50.0, double.infinity);
    // 系数和 = 1.00+1.55+1.55+0.80+0.85+0.90+0.90+1.00 = 8.55
    const sum = 1.00 + 1.55 + 1.55 + 0.80 + 0.85 + 0.90 + 0.90 + 1.00;
    final unit = remaining / sum;
    columnWidths = {
      0: unit * 1.00,             // 发票
      1: unit * 1.55,             // 日期
      2: unit * 1.55,             // 事由
      3: unit * 0.80,             // 金额
      4: unit * 0.85,             // 状态
      5: unit * 0.90,             // 项目
      6: unit * 0.90,             // 类型
      7: unit * 1.00,             // 备注
    };
  }

  /// 从 config/preferences.json 恢复已保存的列宽
  void loadColumnWidths() {
    try {
      final raw = ConfigStorage.instance.getString(_colWidthsKey);
      if (raw != null) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        setState(() {
          columnWidths = decoded.map(
              (k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
          _loadedSavedWidths = true;
        });
      }
    } catch (_) {
      // 解析失败则使用默认比例分配
    }
  }

  /// 保存当前列宽到 config/preferences.json
  void saveColumnWidths() {
    try {
      final encoded =
          json.encode(columnWidths.map((k, v) => MapEntry(k.toString(), v)));
      ConfigStorage.instance.setString(_colWidthsKey, encoded);
      _loadedSavedWidths = true;
    } catch (_) {
      // 保存失败静默忽略
    }
  }
}
