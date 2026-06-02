import 'package:flutter/material.dart';
import '../../../widgets/glass_card.dart';

/// KPI 汇总卡片 — 2×2 布局 + 隐私切换
///
/// 接收原始数据集合，内部计算四项指标后渲染。
/// 使用 [FittedBox] 包裹每个指标块，确保文本溢出时平滑缩放而非截断。
class KpiSummaryCard extends StatelessWidget {
  final List<dynamic> expenses;
  final Map<String, dynamic> summary;
  final bool isPrivacyHidden;
  final VoidCallback onPrivacyToggle;

  const KpiSummaryCard({
    super.key,
    required this.expenses,
    required this.summary,
    required this.isPrivacyHidden,
    required this.onPrivacyToggle,
  });

  @override
  Widget build(BuildContext context) {
    // ── 计算指标（原 _buildKpiCard 逻辑）──
    final double pendingReimburse = expenses
        .where((e) => e['status'] == '待报销' || e['status'] == '核销中')
        .fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());

    final double yearTotal = (summary['total_amount'] as num).toDouble();

    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final double monthTotal = expenses
        .where((e) => (e['incurred_date']?.toString() ?? '').startsWith(prefix))
        .fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());

    final double pending = (summary['pending_amount'] as num).toDouble();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行 + 隐私按钮
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
                onTap: onPrivacyToggle,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isPrivacyHidden ? '🙈 显示金额' : '👁️ 隐藏金额',
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
          // 2×2 指标网格
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: _KpiTile(
                    title: '本月累计 (元)',
                    value: monthTotal,
                    isPrivacyHidden: isPrivacyHidden,
                    trend: '↑ 15%',
                    trendUp: true,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiTile(
                    title: '待开票 (元)',
                    value: pending,
                    isPrivacyHidden: isPrivacyHidden,
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
                  child: _KpiTile(
                    title: '核销中 (元)',
                    value: pendingReimburse,
                    isPrivacyHidden: isPrivacyHidden,
                    trend: '↑ 2%',
                    trendUp: true,
                    color: const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiTile(
                    title: '年度总计 (元)',
                    value: yearTotal,
                    isPrivacyHidden: isPrivacyHidden,
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// 单个 KPI 指标块 — FittedBox 防溢出 + baseline 对齐
// ═══════════════════════════════════════════════════════════════════════════════
class _KpiTile extends StatelessWidget {
  final String title;
  final double value;
  final bool isPrivacyHidden;
  final String? trend;
  final bool trendUp;
  final Color color;

  const _KpiTile({
    required this.title,
    required this.value,
    required this.isPrivacyHidden,
    this.trend,
    this.trendUp = true,
    this.color = const Color(0xFF4F46E5),
  });

  @override
  Widget build(BuildContext context) {
    final display = isPrivacyHidden ? '****' : value.toStringAsFixed(2);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                display,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFamily: 'Consolas',
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: trendUp
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    trend!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: trendUp
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
