import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class InvoiceManagerPage extends StatefulWidget {
  const InvoiceManagerPage({super.key});

  @override
  State<InvoiceManagerPage> createState() => _InvoiceManagerPageState();
}

class _InvoiceManagerPageState extends State<InvoiceManagerPage> {
  List<dynamic> _expenses = [];
  String? _selectedExpenseId;
  String? _previewPdfPath; // 用于右侧预览的本地绝对路径
  bool _isDragging = false; // 是否正在拖拽中（用于 UI 变色反馈）
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  // 获取左侧流水列表
  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/expenses/'));
      if (response.statusCode == 200) {
        setState(() {
          _expenses = json.decode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      _showSnackBar('无法连接到后端，请检查 Python 服务是否运行', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 核心魔法：将拖拽进来的文件路径发送给 Python 后端进行瞬间物理拷贝绑定
  Future<void> _bindInvoice(String filePath) async {
    if (_selectedExpenseId == null) return;

    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/invoices/bind'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'expense_uuuid': _selectedExpenseId,
          'source_file_path': filePath,
        }),
      );

      if (response.statusCode == 201) {
        _showSnackBar('发票绑定成功并已安全存入本地库！');
        // 👉 新增：解析后端返回的数据，获取真正保存到 data/pdfs/ 下的绝对路径
        final responseData = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _previewPdfPath = responseData['saved_path']; 
        });
      } else {
        final error = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar('绑定失败: ${error['detail']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('网络请求失败: $e', isError: true);
    }
  }

  // 👉 新增：去后端查询这笔流水是否已经绑定过 PDF，有的话直接展示
  Future<void> _fetchBoundInvoice(String expenseId) async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/invoices/by-expense/$expenseId'));
      if (response.statusCode == 200) {
        final List<dynamic> invoices = json.decode(utf8.decode(response.bodyBytes));
        if (invoices.isNotEmpty) {
          // 如果数据库里查到了绑定的发票，把绝对路径赋给预览控件
          setState(() {
            _previewPdfPath = invoices.first['saved_path'];
          });
        }
      }
    } catch (e) {
      debugPrint("获取历史发票失败: $e");
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ================= 左侧：流水选择列表 =================
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      '1. 请选择要绑定发票的流水',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            itemCount: _expenses.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final exp = _expenses[index];
                              final isSelected = exp['uuuid'] == _selectedExpenseId;
                              return ListTile(
                                tileColor: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
                                title: Text(exp['title'] ?? '未知记录', 
                                    style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                subtitle: Text('发生日期: ${exp['incurred_date']} | 金额: ¥${exp['amount']}'),
                                trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                                onTap: () {
                                  setState(() {
                                    _selectedExpenseId = exp['uuuid'];
                                    _previewPdfPath = null; // 切换流水时清空右侧预览
                                  });
                                  _fetchBoundInvoice(exp['uuuid']);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),

          // ================= 右侧：DropZone 拖拽区与 PDF 预览 =================
          Expanded(
            flex: 5,
            child: DropTarget(
              onDragEntered: (details) => setState(() => _isDragging = true),
              onDragExited: (details) => setState(() => _isDragging = false),
              onDragDone: (details) async {
                setState(() => _isDragging = false);
                
                // 防呆机制 1：没选流水不准拖拽
                if (_selectedExpenseId == null) {
                  _showSnackBar('请先在左侧列表中选择一笔业务流水！', isError: true);
                  return;
                }
                
                // 防呆机制 2：只取第一个文件，且必须是 PDF
                final XFile file = details.files.first;
                if (!file.path.toLowerCase().endsWith('.pdf')) {
                  _showSnackBar('目前仅支持绑定 PDF 格式的发票！', isError: true);
                  return;
                }

                // 拿到 Windows 本地绝对路径，呼叫 Python 执行瞬间物理拷贝！
                await _bindInvoice(file.path);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: _isDragging 
                      ? Colors.blue.withValues(alpha: 0.2) // 拖拽悬浮时的呼吸反馈
                      : Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isDragging ? Colors.blue : Colors.white.withValues(alpha: 0.4),
                    width: _isDragging ? 3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
                  ],
                ),
                // 动态显示：如果有 PDF 路径则直接渲染内嵌视图，否则显示拖拽提示
                child: _previewPdfPath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: SfPdfViewer.file(File(_previewPdfPath!)),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.upload_file,
                              size: 80,
                              color: _isDragging ? Colors.blue : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _selectedExpenseId == null
                                  ? '请先在左侧选择一笔流水'
                                  : '2. 将 PDF 发票拖拽到此处绑定',
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}