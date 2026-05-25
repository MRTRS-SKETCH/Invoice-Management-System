import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'config.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;
  
  // 核心数据容器
  Map<String, dynamic> _summary = {'total_amount': 0.0, 'pending_amount': 0.0, 'invoice_count': 0};
  List<dynamic> _trend = [];
  List<dynamic> _distribution = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  // 聚合请求三大接口（并行发出）
  Future<void> _fetchDashboardData() async {
    try {
      final base = AppConfig.baseUrl;
      final results = await Future.wait([
        http.get(Uri.parse('$base/api/dashboard/summary')),
        http.get(Uri.parse('$base/api/dashboard/trend')),
        http.get(Uri.parse('$base/api/dashboard/distribution')),
      ]);

      final summaryRes = results[0];
      final trendRes = results[1];
      final distRes = results[2];

      if (summaryRes.statusCode == 200 && trendRes.statusCode == 200 && distRes.statusCode == 200) {
        setState(() {
          _summary = json.decode(utf8.decode(summaryRes.bodyBytes));
          _trend = json.decode(utf8.decode(trendRes.bodyBytes));
          _distribution = json.decode(utf8.decode(distRes.bodyBytes));
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("获取看板数据失败: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('全局看板', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          
          // 1. 顶层统计卡片 (Row 布局)
          Row(
            children: [
              Expanded(child: _buildSummaryCard('累计报销总额', '¥${_summary['total_amount'].toStringAsFixed(2)}', Colors.blueAccent)),
              const SizedBox(width: 16),
              Expanded(child: _buildSummaryCard('待开票/处理中', '¥${_summary['pending_amount'].toStringAsFixed(2)}', Colors.orangeAccent)),
              const SizedBox(width: 16),
              Expanded(child: _buildSummaryCard('绑定发票总数', '${_summary['invoice_count']} 张', Colors.green)),
            ],
          ),
          const SizedBox(height: 24),

          // 2. 图表区域 (分栏布局)
          Expanded(
            child: Row(
              children: [
                // 左侧：近12个月趋势 (柱状图)
                Expanded(
                  flex: 2,
                  child: _buildGlassContainer(
                    title: '近12个月报销趋势',
                    child: _buildTrendChart(),
                  ),
                ),
                const SizedBox(width: 24),
                // 右侧：项目分布占比 (饼图)
                Expanded(
                  flex: 1,
                  child: _buildGlassContainer(
                    title: '报销项目占比',
                    child: _buildDistributionChart(),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- UI 组件封装区 ---

  // 玻璃质感基础容器
  Widget _buildGlassContainer({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(child: child),
        ],
      ),
    );
  }

  // 顶部数据卡片
  Widget _buildSummaryCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.7), color.withValues(alpha: 0.4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // 月度趋势柱状图
  Widget _buildTrendChart() {
    if (_trend.isEmpty) return const Center(child: Text("暂无数据"));
    
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value.toInt() >= _trend.length) return const SizedBox();
                // 截取月份显示, 如 '2026-05' -> '05月'
                String monthStr = '${_trend[value.toInt()]['month'].toString().substring(5)}月';
                return Padding(padding: const EdgeInsets.only(top: 8), child: Text(monthStr, style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        barGroups: _trend.asMap().entries.map((entry) {
          int index = entry.key;
          double amount = entry.value['amount'];
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: amount,
                color: Theme.of(context).colorScheme.primary,
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              )
            ],
          );
        }).toList(),
      ),
    );
  }

  // 项目分布占比图
  Widget _buildDistributionChart() {
    if (_distribution.isEmpty) return const Center(child: Text("暂无数据"));

    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.red, Colors.teal];
    
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: _distribution.asMap().entries.map((entry) {
          int index = entry.key;
          var data = entry.value;
          return PieChartSectionData(
            color: colors[index % colors.length],
            value: data['percentage'] * 100,
            title: '${data['category']}\n${(data['percentage'] * 100).toStringAsFixed(1)}%',
            radius: 50,
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
          );
        }).toList(),
      ),
    );
  }
}