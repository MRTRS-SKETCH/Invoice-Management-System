import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart'; // 确保你的项目中存在 config.dart 并配置了 AppConfig.baseUrl

class ExpenseFlowPage extends StatefulWidget {
  const ExpenseFlowPage({super.key});

  @override
  State<ExpenseFlowPage> createState() => _ExpenseFlowPageState();
}

class _ExpenseFlowPageState extends State<ExpenseFlowPage> {
  // 后端路由前缀，统一从全局配置中读取
  String get _apiUrl => '${AppConfig.baseUrl}/api/expenses/';

  List<dynamic> _expenses = [];
  bool _isLoading = true;

  // ── 搜索与筛选状态 ──
  final TextEditingController _searchController = TextEditingController();
  String? _statusFilter;

  // ── 表单控制器（用于新增记录Dialog） ──
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _amountController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  // 📡 [GET]: 获取开销流水列表
  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);
    try {
      final Map<String, String> params = {'limit': '200'};
      final search = _searchController.text.trim();
      if (search.isNotEmpty) params['search'] = search;
      if (_statusFilter != null && _statusFilter != '全部') {
        params['status'] = _statusFilter!;
      }

      final uri = Uri.parse(_apiUrl).replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _expenses = data;
          _isLoading = false;
        });
      } else {
        throw Exception('服务器状态异常: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('获取流水数据失败: $e', isError: true);
    }
  }

  // 📥 [POST]: 提交流水记录
  Future<void> _addExpense() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': _titleController.text.trim(),
          'amount': double.parse(_amountController.text.trim()),
          'incurred_date': _dateController.text.trim(),
          'status': '待开票',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSnackBar('新增业务流水成功');
        if (mounted) Navigator.pop(context);
        _titleController.clear();
        _amountController.clear();
        _dateController.clear();
        _fetchExpenses();
      } else {
        throw Exception('提交失败: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('新增失败: $e', isError: true);
    }
  }

  // 🔄 [PATCH]: 状态机流转核心引擎
  Future<void> _updateExpenseStatus(String uuuid, String nextStatus) async {
    try {
      final response = await http.patch(
        Uri.parse('$_apiUrl$uuuid'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'status': nextStatus}),
      );

      if (response.statusCode == 200) {
        _showSnackBar('状态已成功推进至 [$nextStatus]');
        _fetchExpenses();
      } else {
        throw Exception('更新失败: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('推进状态失败: $e', isError: true);
    }
  }

  // 🗑️ [DELETE]: 物理删除流水记录
  Future<void> _deleteExpense(String uuuid) async {
    try {
      final response = await http.delete(Uri.parse('$_apiUrl$uuuid'));
      if (response.statusCode == 200) {
        _showSnackBar('记录已成功彻底删除');
        _fetchExpenses();
      } else {
        throw Exception('后端删除失败: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('删除请求异常: $e', isError: true);
    }
  }

  // 🎨 构建动态状态流转按钮
  Widget _buildStatusActionBtn(String uuuid, String currentStatus) {
    if (currentStatus == '待开票') {
      return TextButton.icon(
        icon: const Icon(Icons.receipt, size: 16, color: Colors.green),
        label: const Text(
          '开票',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _updateExpenseStatus(uuuid, '已开票'),
      );
    } else if (currentStatus == '已开票') {
      return TextButton.icon(
        icon: const Icon(
          Icons.assignment_turned_in,
          size: 16,
          color: Colors.blue,
        ),
        label: const Text(
          '去报销',
          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _updateExpenseStatus(uuuid, '核销中'),
      );
    } else if (currentStatus == '核销中') {
      return TextButton.icon(
        icon: const Icon(Icons.done_all, size: 16, color: Colors.purple),
        label: const Text(
          '完结',
          style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _updateExpenseStatus(uuuid, '已完结'),
      );
    }
    return const SizedBox.shrink();
  }

  // ⚠️ 弹出删除确认框
  void _showDeleteConfirmation(String uuuid, String title) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
          child: AlertDialog(
            backgroundColor: Colors.white.withValues(
              alpha: 0.9,
            ), // ✅ 修复 withOpacity 警告
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('确认删除流水？'),
              ],
            ),
            content: Text('你确定要删除事由为“$title”的这条流水记录吗？此操作不可逆！'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(), // ✅ 修复 child 顺序
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () {
                  // ✅ 修复 child 顺序
                  Navigator.of(context).pop();
                  _deleteExpense(uuuid);
                },
                child: const Text(
                  '确认删除',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 📝 弹出新增流水 Dialog
  void _showAddExpenseDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
          child: AlertDialog(
            backgroundColor: Colors.white.withValues(
              alpha: 0.95,
            ), // ✅ 修复 withOpacity 警告
            title: const Text(
              '新增业务开销记录',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: '事由 / 开销名称 *',
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? '请输入事由'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '金额 (元) *',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return '请输入金额';
                      if (double.tryParse(value.trim()) == null)
                        return '请输入合法数字';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dateController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: '发生日期 *',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2101),
                      );
                      if (pickedDate != null) {
                        String formattedDate =
                            "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
                        _dateController.text = formattedDate;
                      }
                    },
                    validator: (value) =>
                        (value == null || value.isEmpty) ? '请选择日期' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(), // ✅ 修复 child 顺序
                child: const Text('取消'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: _addExpense, // ✅ 修复 child 顺序
                child: const Text(
                  '提交保存',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 📊 渲染主数据表格
  Widget _buildDataTable() {
    if (_expenses.isEmpty) {
      return const Center(
        child: Text(
          '暂无匹配的开销记录流水',
          style: TextStyle(color: Colors.black54, fontSize: 16),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical, // 默认其实就是 vertical，写上更清晰
      // 内层：负责水平方向滚动 (左右)
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Colors.grey.withValues(alpha: 0.08),
          ), // ✅ 修复 withOpacity
          dataRowMaxHeight: 56,
          columns: const [
            DataColumn(
              label: Text(
                '事由 / 开销名称',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text('金额', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            DataColumn(
              label: Text(
                '发生日期',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                '当前状态',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                '唯一标识 (UUID)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text('操作列', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
          rows: _expenses.map((expense) {
            final uuuid = expense['uuuid']?.toString() ?? '';
            final title = expense['title']?.toString() ?? '无事由';
            final status = expense['status']?.toString() ?? '待开票';

            Color statusColor = Colors.grey;
            switch (status) {
              case '待开票':
                statusColor = Colors.orange;
                break;
              case '已开票':
                statusColor = Colors.green;
                break;
              case '核销中':
                statusColor = Colors.blue;
                break;
              case '已完结':
                statusColor = Colors.purple;
                break;
            }

            return DataRow(
              cells: [
                DataCell(
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                DataCell(
                  Text(
                    '￥${expense['amount']?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(
                      fontFamily: 'Roboto Mono',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal,
                    ),
                  ),
                ),
                DataCell(Text(expense['incurred_date']?.toString() ?? '-')),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(
                        alpha: 0.15,
                      ), // ✅ 修复 withOpacity
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    uuuid.length > 8
                        ? '${uuuid.substring(0, 8)}...'
                        : (uuuid.isEmpty ? '-' : uuuid),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusActionBtn(uuuid, status),
                      if (uuuid.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Colors.redAccent,
                          tooltip: '删除记录',
                          onPressed: () =>
                              _showDeleteConfirmation(uuuid, title),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶层动作栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '业务流水记账看板',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '桌面端全生命周期状态流转系统',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('新增一条流水'),
                onPressed: _showAddExpenseDialog,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 高级动态筛选组件
          Card(
            elevation: 0,
            color: Colors.grey.withValues(alpha: 0.06), // ✅ 修复 withOpacity
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 6.0,
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.black38, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: '按名称/事由进行高频关键字过滤...',
                        border: InputBorder.none,
                      ),
                      onChanged: (val) => _fetchExpenses(),
                    ),
                  ),
                  // ✅ 修复 VerticalDivider 高度报错，外面包一层 SizedBox(height: 20)
                  const SizedBox(
                    height: 20,
                    child: VerticalDivider(thickness: 1, width: 1),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _statusFilter ?? '全部',
                    underline: const SizedBox(),
                    icon: const Icon(Icons.filter_alt_outlined, size: 18),
                    // ✅ 修复 black85 报错 -> 改成了标准的 black87
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                    items: <String>['全部', '待开票', '已开票', '核销中', '已完结'].map((
                      String value,
                    ) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _statusFilter = newValue == '全部' ? null : newValue;
                      });
                      _fetchExpenses();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 核心网格视图区
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    )
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      child: _buildDataTable(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Toast 轻提示
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
