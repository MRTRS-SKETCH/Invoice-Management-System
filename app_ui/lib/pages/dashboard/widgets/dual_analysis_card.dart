import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../widgets/glass_card.dart';

/// 双维分析卡片 — 项目进度条 + 类型环形图 + 时间范围切换
///
/// 左侧展示 Top 3 开销项目的横向进度条，
/// 右侧展示开销类型的 Donut 环形图及其图例。
/// 标题栏带时间范围下拉框，切换时通过 [onTimeRangeChanged] 通知父级。
class DualAnalysisCard extends StatelessWidget {
  final List<dynamic> distribution;
  final List<dynamic> typeDistribution;
  final String analysisTimeRange;
  final ValueChanged<String?> onTimeRangeChanged;

  static const _timeRanges = ['本月', '本季', '本年'];

  const DualAnalysisCard({
    super.key,
    required this.distribution,
    required this.typeDistribution,
    required this.analysisTimeRange,
    required this.onTimeRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Top 3 项目
    final top3 = distribution.take(3).toList();
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
          // 标题行 + 时间范围下拉
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '多维开销分析',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(
                height: 28,
                child: DropdownButton<String>(
                  value: analysisTimeRange,
                  underline: const SizedBox(),
                  isDense: true,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF4F46E5)),
                  items: _timeRanges
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: onTimeRangeChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                  child: typeDistribution.isEmpty
                      ? const Center(
                          child: Text('暂无数据',
                              style: TextStyle(
                                  color: Colors.black38, fontSize: 11)))
                      : _buildDonutWithLegend(typeDistribution, donutColors),
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
    return Column(
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
    );
  }
}
