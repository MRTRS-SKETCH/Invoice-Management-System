import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'config.dart';
import 'logger.dart';

class InvoiceManagerPage extends StatefulWidget {
  const InvoiceManagerPage({super.key});

  @override
  State<InvoiceManagerPage> createState() => _InvoiceManagerPageState();
}

class _InvoiceManagerPageState extends State<InvoiceManagerPage> {
  List<dynamic> _expenses = [];
  bool _isLoading = false;

  // ── ValueNotifier：隔离右侧面板状态，避免全局 setState 连累 PDF 组件 ──
  final _selectedExpenseNotifier = ValueNotifier<String?>(null);
  final _invoicesNotifier = ValueNotifier<List<dynamic>>([]);
  final _selectedInvoiceIndexNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  @override
  void dispose() {
    _selectedExpenseNotifier.dispose();
    _invoicesNotifier.dispose();
    _selectedInvoiceIndexNotifier.dispose();
    super.dispose();
  }

  // 获取左侧流水列表（仅影响左侧面板，使用父级 setState）
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
    final expenseId = _selectedExpenseNotifier.value;
    if (expenseId == null) return;

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/bind'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'expense_uuuid': expenseId,
          'source_file_path': filePath,
        }),
      );

      if (response.statusCode == 201) {
        _showSnackBar('发票绑定成功并已安全存入本地库！');
        _fetchBoundInvoices(expenseId);
      } else {
        final error = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar('绑定失败: ${error['detail']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('网络请求失败: $e', isError: true);
    }
  }

  // 查询该流水绑定的所有发票（仅更新 notifier，不触发父级 setState）
  Future<void> _fetchBoundInvoices(String expenseId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/by-expense/$expenseId'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> invoices = json.decode(utf8.decode(response.bodyBytes));
        _invoicesNotifier.value = invoices;
        _selectedInvoiceIndexNotifier.value = 0;
      }
    } catch (e) {
      AppLogger.error("获取历史发票失败", e);
    }
  }

  // 解绑单张发票（通过回调暴露给右侧面板）
  Future<void> _deleteInvoice(String invoiceUuid) async {
    // 强制销毁右侧的 PDF 预览组件，释放 Windows 底部文件锁
    _selectedInvoiceIndexNotifier.value = -1;

    // 稍微等待 150 毫秒，确保 Flutter 的渲染树完成卸载并彻底释放了文件占用
    await Future.delayed(const Duration(milliseconds: 150));

    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/$invoiceUuid'),
      );
      if (response.statusCode == 200) {
        _showSnackBar('发票已解绑并成功删除');
        final expenseId = _selectedExpenseNotifier.value;
        if (expenseId != null) {
          _fetchBoundInvoices(expenseId);
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
                              // 使用 ValueListenableBuilder 仅刷新选中高亮，不触发右侧 PDF 重建
                              return ValueListenableBuilder<String?>(
                                valueListenable: _selectedExpenseNotifier,
                                builder: (context, selectedId, _) {
                                  final isSelected = exp['uuuid'] == selectedId;
                                  return ListTile(
                                    tileColor: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
                                    title: Text(exp['title'] ?? '未知记录',
                                        style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                    subtitle: Text(
                                        '发生日期: ${exp['incurred_date']} | 金额: ¥${exp['amount']}'),
                                    trailing:
                                        isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                                    onTap: () {
                                      _selectedExpenseNotifier.value = exp['uuuid'];
                                      _invoicesNotifier.value = [];
                                      _selectedInvoiceIndexNotifier.value = 0;
                                      _fetchBoundInvoices(exp['uuuid']);
                                    },
                                  );
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

          // ================= 右侧：发票面板（独立组件，局部刷新）=================
          Expanded(
            flex: 5,
            child: _InvoiceRightPanel(
              selectedExpenseNotifier: _selectedExpenseNotifier,
              invoicesNotifier: _invoicesNotifier,
              selectedInvoiceIndexNotifier: _selectedInvoiceIndexNotifier,
              onBindInvoice: _bindInvoice,
              onDeleteInvoice: _deleteInvoice,
              showSnackBar: _showSnackBar,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
/// 右侧面板 — 独立 [StatefulWidget]
///
/// 内部通过 [ValueListenableBuilder] 监听 notifier 变化实现局部刷新。
/// 左侧列表选中操作仅更新 notifier 值，不会触发此组件父级重建，
/// 从而避免重量级 [SfPdfViewer] 被连累 Rebuild 导致的卡顿/闪烁。
// ═══════════════════════════════════════════════════════════════════════════════
class _InvoiceRightPanel extends StatefulWidget {
  final ValueNotifier<String?> selectedExpenseNotifier;
  final ValueNotifier<List<dynamic>> invoicesNotifier;
  final ValueNotifier<int> selectedInvoiceIndexNotifier;
  final Future<void> Function(String filePath) onBindInvoice;
  final Future<void> Function(String invoiceUuid) onDeleteInvoice;
  final void Function(String message, {bool isError}) showSnackBar;

  const _InvoiceRightPanel({
    required this.selectedExpenseNotifier,
    required this.invoicesNotifier,
    required this.selectedInvoiceIndexNotifier,
    required this.onBindInvoice,
    required this.onDeleteInvoice,
    required this.showSnackBar,
  });

  @override
  State<_InvoiceRightPanel> createState() => _InvoiceRightPanelState();
}

class _InvoiceRightPanelState extends State<_InvoiceRightPanel> {
  // 拖拽态仅影响本组件内部，不会泄漏到父级
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 发票缩略图列表（监听 invoices + selectedIndex）──
        ValueListenableBuilder<List<dynamic>>(
          valueListenable: widget.invoicesNotifier,
          builder: (context, invoices, _) {
            if (invoices.isEmpty) return const SizedBox.shrink();
            return ValueListenableBuilder<int>(
              valueListenable: widget.selectedInvoiceIndexNotifier,
              builder: (context, selectedIndex, _) {
                return Container(
                  height: 56,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: invoices.length,
                    separatorBuilder: (_, _) => const VerticalDivider(width: 1),
                    itemBuilder: (ctx, index) {
                      final inv = invoices[index];
                      final isActive = index == selectedIndex;
                      final fileName = inv['file_name'] ?? '未知文件';
                      return InkWell(
                        onTap: () => widget.selectedInvoiceIndexNotifier.value = index,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: isActive ? Colors.blue.withValues(alpha: 0.15) : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.picture_as_pdf,
                                  color: isActive ? Colors.blue : Colors.red, size: 20),
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
                                onPressed: () => widget.onDeleteInvoice(inv['uuuid']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
        // ── DropZone + PDF 预览 ──
        Expanded(
          child: ValueListenableBuilder<String?>(
            valueListenable: widget.selectedExpenseNotifier,
            builder: (context, selectedExpenseId, _) {
              return ValueListenableBuilder<List<dynamic>>(
                valueListenable: widget.invoicesNotifier,
                builder: (context, invoices, _) {
                  return ValueListenableBuilder<int>(
                    valueListenable: widget.selectedInvoiceIndexNotifier,
                    builder: (context, selectedIndex, _) {
                      // 计算当前 PDF 预览路径
                      String? previewPath;
                      if (invoices.isNotEmpty &&
                          selectedIndex >= 0 &&
                          selectedIndex < invoices.length) {
                        previewPath = invoices[selectedIndex]['saved_path'] as String?;
                      }

                      return DropTarget(
                        onDragEntered: (_) => setState(() => _isDragging = true),
                        onDragExited: (_) => setState(() => _isDragging = false),
                        onDragDone: (details) async {
                          setState(() => _isDragging = false);
                          if (selectedExpenseId == null) {
                            widget.showSnackBar('请先在左侧列表中选择一笔业务流水！', isError: true);
                            return;
                          }
                          final XFile file = details.files.first;
                          if (!file.path.toLowerCase().endsWith('.pdf')) {
                            widget.showSnackBar('目前仅支持绑定 PDF 格式的发票！', isError: true);
                            return;
                          }
                          await widget.onBindInvoice(file.path);
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
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
                            ],
                          ),
                          child: previewPath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: SfPdfViewer.file(File(previewPath)),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.upload_file,
                                          size: 80,
                                          color: _isDragging
                                              ? Colors.blue
                                              : Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text(
                                        selectedExpenseId == null
                                            ? '请先在左侧选择一笔流水'
                                            : '2. 将 PDF 发票拖拽到此处绑定',
                                        style: TextStyle(
                                            fontSize: 20,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
