import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../widgets/glass_card.dart';

/// 双维分析卡片 — 项目进度条 + 类型环形图 + 时间范围切换 + 日期区间
///
/// 左侧展示 Top 3 开销项目的横向进度条，
/// 右侧展示开销类型的 Donut 环形图及其图例。
/// 标题栏带时间范围下拉框 + 起止日期选择器，
/// 时间范围变更时自动联动明细表的日期区间。
class DualAnalysisCard extends StatefulWidget {
  final List<dynamic> distribution;
  final List<dynamic> typeDistribution;
  final String analysisTimeRange;
  final String? dateFrom;
  final String? dateTo;
  final ValueChanged<String?> onTimeRangeChanged;
  final void Function(String? from, String? to) onDateRangeChanged;

  static const _timeRanges = ['近7天', '近30天', '近60天', '近3月', '近1年', '总计'];

  /// 时间范围 → 天数映射，供父级调用 API 时使用（总计 → null）
  static int? daysFor(String range) {
    const map = {
      '近7天': 7,
      '近30天': 30,
      '近60天': 60,
      '近3月': 90,
      '近1年': 365,
      '总计': null,
    };
    return map[range];
  }

  /// 根据时间范围标签计算起止日期字符串
  static ({String from, String to})? dateRangeFor(String range) {
    if (range == '总计') return null;
    final days = daysFor(range);
    if (days == null) return null;
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days));
    return (
      from:
          '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
      to:
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );
  }

  const DualAnalysisCard({
    super.key,
    required this.distribution,
    required this.typeDistribution,
    required this.analysisTimeRange,
    this.dateFrom,
    this.dateTo,
    required this.onTimeRangeChanged,
    required this.onDateRangeChanged,
  });

  @override
  State<DualAnalysisCard> createState() => _DualAnalysisCardState();
}

class _DualAnalysisCardState extends State<DualAnalysisCard> {
  String? _from;
  String? _to;

  @override
  void initState() {
    super.initState();
    _from = widget.dateFrom;
    _to = widget.dateTo;
  }

  @override
  void didUpdateWidget(covariant DualAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateFrom != widget.dateFrom) _from = widget.dateFrom;
    if (oldWidget.dateTo != widget.dateTo) _to = widget.dateTo;
  }

  /// 弹出日期范围选择器
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(
              start: DateTime.tryParse(_from!) ?? now.subtract(const Duration(days: 30)),
              end: DateTime.tryParse(_to!) ?? now,
            )
          : null,
      helpText: '选择时间范围',
      saveText: '确定',
    );
    if (range != null) {
      final f =
          '${range.start.year}-${range.start.month.toString().padLeft(2, '0')}-${range.start.day.toString().padLeft(2, '0')}';
      final t =
          '${range.end.year}-${range.end.month.toString().padLeft(2, '0')}-${range.end.day.toString().padLeft(2, '0')}';
      setState(() {
        _from = f;
        _to = t;
      });
      widget.onDateRangeChanged(f, t);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Top 3 项目
    final top3 = widget.distribution.take(3).toList();
    final maxAmt = top3.isNotEmpty
        ? top3
            .map((d) => (d['amount'] as num).toDouble())
            .reduce((a, b) => a > b ? a : b)
        : 1.0;

    // 环形图色板
    const donutColors = [
      Color(0xFF4F46E5),
      Color(0xFF0EA5E9),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
    ];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行 + 时间范围下拉 + 日期区间
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '多维开销分析',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(
                height: 28,
                child: DropdownButton<String>(
                  value: widget.analysisTimeRange,
                  underline: const SizedBox(),
                  isDense: true,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF4F46E5)),
                  items: DualAnalysisCard._timeRanges
                      .map(
                          (r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      // 时间范围变更 → 自动联动日期区间，清除手动日期
                      final dr = DualAnalysisCard.dateRangeFor(v);
                      setState(() {
                        _from = dr?.from;
                        _to = dr?.to;
                      });
                      widget.onDateRangeChanged(dr?.from, dr?.to);
                      widget.onTimeRangeChanged(v);
                    }
                  },
                ),
              ),
              // 日历按钮 — 点击弹出日期范围选择器
              if (_from == null)
                IconButton(
                  icon: const Icon(Icons.date_range, size: 18),
                  tooltip: '选择日期范围',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: _pickDateRange,
                ),
              if (_from != null)
                Container(
                  height: 22,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    InkWell(
                      onTap: _pickDateRange,
                      child: Text(
                        '$_from ~ $_to',
                        style: const TextStyle(
                            fontSize: 9, color: Color(0xFF4F46E5)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _from = null;
                          _to = null;
                        });
                        widget.onDateRangeChanged(null, null);
                      },
                      child: const Icon(Icons.close,
                          size: 10, color: Color(0xFF94A3B8)),
                    ),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              children: [
                // ── 左半：项目进度条 ──
                Expanded(
                  flex: 12,
                  child: top3.isEmpty
                      ? const Center(
                          child: Text('暂无数据',
                              style: TextStyle(
                                  color: Colors.black38, fontSize: 11)))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children:
                              top3.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final data = entry.value;
                            final pct = maxAmt > 0
                                ? ((data['amount'] as num).toDouble() / maxAmt)
                                : 0.0;
                            const barColors = [
                              Color(0xFF4F46E5),
                              Color(0xFF0EA5E9),
                              Color(0xFF10B981),
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
                                      backgroundColor:
                                          const Color(0xFFF1F5F9),
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
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
                // ── 右半：环形图 + 图例 ──
                Expanded(
                  flex: 8,
                  child: widget.typeDistribution.isEmpty
                      ? const Center(
                          child: Text('暂无数据',
                              style: TextStyle(
                                  color: Colors.black38, fontSize: 11)))
                      : _buildDonutWithLegend(widget.typeDistribution, donutColors),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 环形图 + 下方图例
  static Widget _buildDonutWithLegend(
      List<dynamic> data, List<Color> colors) {
    // 用数据哈希做 key，只在数据变化时重建
    final dataKey = ValueKey(data.hashCode);
    return RepaintBoundary(
      key: dataKey,
      child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 70,
          height: 70,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 22,
              sections: data.asMap().entries.map((entry) {
                final i = entry.key;
                final d = entry.value;
                return PieChartSectionData(
                  color: colors[i % colors.length],
                  value: (d['percentage'] as num).toDouble() * 100,
                  title: '',
                  radius: 14,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          alignment: WrapAlignment.center,
          children: data.asMap().entries.map((entry) {
            final i = entry.key;
            final d = entry.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors[i % colors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  d['category']?.toString() ?? '-',
                  style:
                      const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    ),
  );
  }
}
