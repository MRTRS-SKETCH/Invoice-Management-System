import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'config.dart';

class InvoiceManagerPage extends StatefulWidget {
  const InvoiceManagerPage({super.key});

  @override
  State<InvoiceManagerPage> createState() => _InvoiceManagerPageState();
}

class _InvoiceManagerPageState extends State<InvoiceManagerPage> {
  List<dynamic> _expenses = [];
  String? _selectedExpenseId;
  List<dynamic> _invoices = []; // 当前流水绑定的所有发票
  int _selectedInvoiceIndex = 0; // 当前预览的发票索引
  bool _isDragging = false;
  bool _isLoading = false;

  String get _previewPdfPath {
    if (_invoices.isNotEmpty && _selectedInvoiceIndex < _invoices.length) {
      return _invoices[_selectedInvoiceIndex]['saved_path'] as String?;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  // 获取左侧流水列表
  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${AppConfig.baseUrl}/api/expenses/'));
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
        Uri.parse('${AppConfig.baseUrl}/api/invoices/bind'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'expense_uuuid': _selectedExpenseId,
          'source_file_path': filePath,
        }),
      );

      if (response.statusCode == 201) {
        _showSnackBar('发票绑定成功并已安全存入本地库！');
        // 绑定成功后刷新整组发票列表
        _fetchBoundInvoices(_selectedExpenseId!);
      } else {
        final error = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar('绑定失败: ${error['detail']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('网络请求失败: $e', isError: true);
    }
  }

  // 查询该流水绑定的所有发票
  Future<void> _fetchBoundInvoices(String expenseId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/by-expense/$expenseId'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> invoices = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _invoices = invoices;
          _selectedInvoiceIndex = 0;
        });
      }
    } catch (e) {
      debugPrint("获取历史发票失败: $e");
    }
  }

  // 解绑单张发票
  Future<void> _deleteInvoice(String invoiceUuid) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/$invoiceUuid'),
      );
      if (response.statusCode == 200) {
        _showSnackBar('发票已解绑并删除');
        // 重新拉取发票列表
        if (_selectedExpenseId != null) {
          _fetchBoundInvoices(_selectedExpenseId!);
        }
      } else {
        _showSnackBar('解绑失败', isError: true);
      }
    } catch (e) {
      _showSnackBar('网络请求失败: $e', isError: true);
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
                                    _invoices = [];
                                    _selectedInvoiceIndex = 0;
                                  });
                                  _fetchBoundInvoices(exp['uuuid']);
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

          // ================= 右侧：发票列表 + DropZone + PDF 预览 =================
          Expanded(
            flex: 5,
            child: Column(
              children: [
                // ── 发票缩略图列表 ──
                if (_invoices.isNotEmpty)
                  Container(
                    height: 56,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _invoices.length,
                      separatorBuilder: (_, _) => const VerticalDivider(width: 1),
                      itemBuilder: (ctx, index) {
                        final inv = _invoices[index];
                        final isActive = index == _selectedInvoiceIndex;
                        final fileName = inv['file_name'] ?? '未知文件';
                        return InkWell(
                          onTap: () => setState(() => _selectedInvoiceIndex = index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            color: isActive ? Colors.blue.withValues(alpha: 0.15) : null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.picture_as_pdf, color: isActive ? Colors.blue : Colors.red, size: 20),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 180),
                                  child: Text(
                                    fileName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  color: Colors.redAccent,
                                  tooltip: '解绑删除',
                                  onPressed: () => _deleteInvoice(inv['uuuid']),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                // ── DropZone + PDF 预览 ──
                Expanded(
                  child: DropTarget(
                    onDragEntered: (details) => setState(() => _isDragging = true),
                    onDragExited: (details) => setState(() => _isDragging = false),
                    onDragDone: (details) async {
                      setState(() => _isDragging = false);
                      if (_selectedExpenseId == null) {
                        _showSnackBar('请先在左侧列表中选择一笔业务流水！', isError: true);
                        return;
                      }
                      final XFile file = details.files.first;
                      if (!file.path.toLowerCase().endsWith('.pdf')) {
                        _showSnackBar('目前仅支持绑定 PDF 格式的发票！', isError: true);
                        return;
                      }
                      await _bindInvoice(file.path);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isDragging
                            ? Colors.blue.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isDragging ? Colors.blue : Colors.white.withValues(alpha: 0.4),
                          width: _isDragging ? 3 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
                        ],
                      ),
                      child: _previewPdfPath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: SfPdfViewer.file(File(_previewPdfPath!)),
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.upload_file, size: 80,
                                      color: _isDragging ? Colors.blue : Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    _selectedExpenseId == null
                                        ? '请先在左侧选择一笔流水'
                                        : '2. 将 PDF 发票拖拽到此处绑定',
                                    style: TextStyle(fontSize: 20, color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                    ),
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