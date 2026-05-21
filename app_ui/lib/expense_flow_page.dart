import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ExpenseFlowPage extends StatefulWidget {
  const ExpenseFlowPage({super.key});

  @override
  State<ExpenseFlowPage> createState() => _ExpenseFlowPageState();
}

class _ExpenseFlowPageState extends State<ExpenseFlowPage> {
  // 绑定 Python 后端路由前缀 (根据之前的设定)
  final String apiUrl = 'http://127.0.0.1:8000/api/expenses/';
  
  List<dynamic> _expenses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  // GET: 获取开销流水列表
  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        // 使用 utf8.decode 防止中文乱码
        setState(() {
          _expenses = jsonDecode(utf8.decode(response.bodyBytes));
        });
      } else {
        _showError('获取数据失败: ${response.statusCode}');
      }
    } catch (e) {
      _showError('无法连接到本地服务，请确保 Python 后端已启动\n错误: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // POST: 提交新增开销
  Future<void> _addExpense(String name, double amount) async {
    try {
      final String today = DateTime.now().toIso8601String().split('T')[0];
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'title': name,
          'amount': amount,
          'incurred_date': today,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 新增成功后，重新拉取最新列表
        _fetchExpenses();
      } else {
        _showError('新增失败: ${response.body}');
      }
    } catch (e) {
      _showError('提交异常: $e');
    }
  }

  // 辅助函数：显示错误弹窗
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  // 显示新增记录的毛玻璃弹窗
  void _showAddDialog() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        // 弹窗也使用毛玻璃效果
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.8),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('新增业务流水'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '开销事由',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '发生金额 (¥)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final amount = double.tryParse(amountController.text) ?? 0.0;
                  if (name.isNotEmpty && amount > 0) {
                    _addExpense(name, amount);
                    Navigator.pop(context);
                  }
                },
                child: const Text('提交'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 外层容器，提供基础的背景环境
    return Container(
      padding: const EdgeInsets.all(24.0),
      // 这里可以放一张淡雅的背景图，毛玻璃效果会更惊艳。现在用渐变色代替。
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.purple.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部操作栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '业务流水 (Expense Flow)',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              FilledButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add_card),
                label: const Text('新增记录'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 核心数据表格：毛玻璃容器
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24), // 圆角裁切必须有
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0), // 核心模糊属性
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.4), // 半透明白色底
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5), // 高光描边
                  ),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _expenses.isEmpty
                          ? const Center(child: Text('暂无开销记录，请点击右上角新增。'))
                          : _buildDataTable(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建 DataTable 视图
  Widget _buildDataTable() {
    return SingleChildScrollView(
      child: DataTable(
        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        dataRowMaxHeight: 60, // 稍微增高行距，适合桌面端点击
        columns: const [
          DataColumn(label: Text('事由')),
          DataColumn(label: Text('金额')),
          DataColumn(label: Text('发生日期')),
          DataColumn(label: Text('状态')),
          DataColumn(label: Text('唯一标识')),
        ],
        rows: _expenses.map((expense) {
          // 状态标签的颜色逻辑
          final status = expense['status'] ?? '未知';
          Color statusColor = Colors.grey;
          if (status == '待开票') statusColor = Colors.orange;
          if (status == '已开票') statusColor = Colors.blue;
          if (status == '核销中') statusColor = Colors.purple;
          if (status == '已完结') statusColor = Colors.green;

          return DataRow(cells: [
            DataCell(Text(expense['title'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
            DataCell(Text('¥ ${expense['amount']?.toString() ?? '0.00'}', 
              style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold))),
            DataCell(Text(expense['incurred_date'] ?? '-')),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
            DataCell(Text(
                expense['uuuid'] != null && expense['uuuid'].toString().length > 8
                    ? '${expense['uuuid'].toString().substring(0, 8)}...'
                    : (expense['uuuid'] ?? '-').toString(),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
            )),
          ]);
        }).toList(),
      ),
    );
  }
}