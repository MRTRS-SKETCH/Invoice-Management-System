import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class ExpenseFlowPage extends StatefulWidget {
  const ExpenseFlowPage({super.key});

  @override
  State<ExpenseFlowPage> createState() => _ExpenseFlowPageState();
}

class _ExpenseFlowPageState extends State<ExpenseFlowPage> {
  // 后端路由前缀（统一使用全局配置）
  String get _apiUrl => '${AppConfig.baseUrl}/api/expenses/';

  List<dynamic> _expenses = [];
  bool _isLoading = true;

  // ── 筛选状态 ──
  final TextEditingController _searchController = TextEditingController();
  String? _statusFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  // GET: 获取开销流水列表（携带筛选参数）
  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);
    try {
      final params = <String, String>{};
      params['limit'] = '5000';  // 防止后端默认截断 100 条
      final search = _searchController.text.trim();
      if (search.isNotEmpty) params['search'] = search;
      if (_statusFilter != null) params['status'] = _statusFilter!;
      if (_dateFrom != null) params['date_from'] = _dateFrom!.toIso8601String().split('T')[0];
      if (_dateTo != null) params['date_to'] = _dateTo!.toIso8601String().split('T')[0];

      final uri = Uri.parse(_apiUrl).replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri);
      if (response.statusCode == 200) {
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
        Uri.parse(_apiUrl),
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

  // PATCH: 局部更新开销状态 (状态流转)
  Future<void> _updateExpenseStatus(String uuuid, String newStatus) async {
    try {
      final response = await http.patch(
        Uri.parse('$_apiUrl$uuuid'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'status': newStatus}),
      );

      if (response.statusCode == 200) {
        // 零延迟内存更新：直接修改对应 item 的 status，无需全量刷新
        setState(() {
          final idx = _expenses.indexWhere((item) => item['uuuid'] == uuuid);
          if (idx != -1) _expenses[idx]['status'] = newStatus;
        });
      } else {
        _showError('状态流转失败: ${response.body}');
      }
    } catch (e) {
      _showError('网络异常: $e');
    }
  }

  // DELETE: 删除开销记录
  Future<void> _deleteExpense(String uuuid) async {
    try {
      final response = await http.delete(Uri.parse('$_apiUrl$uuuid'));
      if (response.statusCode == 200) {
        // 零延迟内存更新：直接从列表中移除，无需全量刷新
        setState(() {
          _expenses.removeWhere((item) => item['uuuid'] == uuuid);
        });
      } else {
        _showError('删除失败: ${response.body}');
      }
    } catch (e) {
      _showError('网络异常: $e');
    }
  }

  // 辅助函数：显示错误弹窗
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  /// 状态流转确认弹窗 — 防止误操作
  void _showStatusConfirmDialog(String uuuid, String currentStatus, String nextStatus, String btnText) {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('确认状态变更'),
          content: Text('确定要将该笔流水从「$currentStatus」变更为「$nextStatus」吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateExpenseStatus(uuuid, nextStatus);
              },
              child: Text(btnText),
            ),
          ],
        ),
      ),
    );
  }

  // UI: 显示新增记录的毛玻璃弹窗
  void _showAddDialog() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
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

  // UI: 显示删除确认的毛玻璃弹窗 (防呆设计)
  void _showDeleteConfirmDialog(String uuuid, String expenseTitle) {
    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('删除确认'),
            content: Text('确定要删除“$expenseTitle”这笔流水吗？此操作不可逆。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () {
                  Navigator.pop(context); // 先关闭弹窗
                  _deleteExpense(uuuid);  // 再执行删除请求
                },
                child: const Text('确认删除'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建筛选栏
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          // 搜索框
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索事由...',
                prefixIcon: Icon(Icons.search, size: 20),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => _fetchExpenses(),
            ),
          ),
          const SizedBox(width: 12),
          // 状态下拉
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String?>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              hint: const Text('全部状态'),
              items: const [
                DropdownMenuItem(value: null, child: Text('全部状态')),
                DropdownMenuItem(value: '待开票', child: Text('待开票')),
                DropdownMenuItem(value: '已开票', child: Text('已开票')),
                DropdownMenuItem(value: '待报销', child: Text('待报销')),
                DropdownMenuItem(value: '核销中', child: Text('核销中')),
                DropdownMenuItem(value: '已完结', child: Text('已完结')),
              ],
              onChanged: (v) {
                setState(() => _statusFilter = v);
                _fetchExpenses();
              },
            ),
          ),
          const SizedBox(width: 12),
          // 日期范围
          SizedBox(
            width: 160,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(_dateFrom != null
                  ? _dateFrom!.toIso8601String().split('T')[0]
                  : '开始日期'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dateFrom ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _dateFrom = picked);
                  _fetchExpenses();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          const Text('—', style: TextStyle(color: Colors.grey)),
          const SizedBox(width: 8),
          SizedBox(
            width: 160,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(_dateTo != null
                  ? _dateTo!.toIso8601String().split('T')[0]
                  : '结束日期'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dateTo ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _dateTo = picked);
                  _fetchExpenses();
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          // 清除筛选
          if (_statusFilter != null || _dateFrom != null || _dateTo != null)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: '清除筛选',
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _statusFilter = null;
                  _dateFrom = null;
                  _dateTo = null;
                });
                _fetchExpenses();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
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
          const SizedBox(height: 16),
          // 筛选栏
          _buildFilterBar(),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
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
        dataRowMaxHeight: 60,
        columns: const [
          DataColumn(label: Text('事由')),
          DataColumn(label: Text('金额')),
          DataColumn(label: Text('发生日期')),
          DataColumn(label: Text('状态')),
          DataColumn(label: Text('唯一标识')),
          DataColumn(label: Text('操作')), // 新增的操作列
        ],
        rows: _expenses.map((expense) {
          final status = expense['status'] ?? '未知';
          final title = expense['title'] ?? '-';
          final uuuid = expense['uuuid']?.toString() ?? '';
          
          Color statusColor = Colors.grey;
          if (status == '待开票') statusColor = Colors.orange;
          if (status == '已开票') statusColor = Colors.blue;
          if (status == '待报销') statusColor = Colors.deepOrange;
          if (status == '核销中') statusColor = Colors.purple;
          if (status == '已完结') statusColor = Colors.green;

          return DataRow(cells: [
            DataCell(Text(title, style: const TextStyle(fontWeight: FontWeight.w500))),
            DataCell(Text('¥ ${expense['amount']?.toString() ?? '0.00'}', 
              style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold))),
            DataCell(Text(expense['incurred_date'] ?? '-')),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
            DataCell(Text(
                uuuid.length > 8 ? '${uuuid.substring(0, 8)}...' : uuuid,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
            )),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusActionBtn(uuuid, status), // 动态状态流转按钮
                  if (uuuid.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.redAccent,
                      tooltip: '删除记录',
                      onPressed: () => _showDeleteConfirmDialog(uuuid, title),
                    ),
                ],
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  // 辅助组件：根据当前状态，动态生成下一步的流转按钮（五段状态机）
  Widget _buildStatusActionBtn(String uuuid, String currentStatus) {
    if (uuuid.isEmpty) return const SizedBox.shrink();

    String nextStatus = '';
    String btnText = '';
    Color btnColor = Colors.grey;
    IconData btnIcon = Icons.arrow_forward;

    if (currentStatus == '待开票') {
      nextStatus = '已开票';
      btnText = '开票';
      btnColor = Colors.blue;
      btnIcon = Icons.receipt_long;
    } else if (currentStatus == '已开票') {
      nextStatus = '待报销';
      btnText = '待报销';
      btnColor = Colors.deepOrange;
      btnIcon = Icons.assignment_late;
    } else if (currentStatus == '待报销') {
      nextStatus = '核销中';
      btnText = '去报销';
      btnColor = Colors.purple;
      btnIcon = Icons.account_balance_wallet;
    } else if (currentStatus == '核销中') {
      nextStatus = '已完结';
      btnText = '完结';
      btnColor = Colors.green;
      btnIcon = Icons.check_circle;
    }

    if (nextStatus.isEmpty) {
      return const SizedBox(width: 80, child: Center(child: Text('-', style: TextStyle(color: Colors.grey))));
    }

    // 点击先弹确认窗，防止误操作
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: btnColor,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      icon: Icon(btnIcon, size: 16),
      label: Text(btnText, style: const TextStyle(fontWeight: FontWeight.bold)),
      onPressed: () => _showStatusConfirmDialog(uuuid, currentStatus, nextStatus, btnText),
    );
  }
}