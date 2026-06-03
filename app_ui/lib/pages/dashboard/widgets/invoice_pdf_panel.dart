import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../widgets/glass_card.dart';

/// PDF 发票预览面板 — 缩略图条 + 拖拽绑票 + 原文件秒开预览
///
/// 接收当前选中流水的发票列表及索引，通过回调通知父级进行
/// 切换、删除、拖拽绑定操作。内部管理拖拽高亮动画。
class InvoicePdfPanel extends StatefulWidget {
  final String? selectedExpenseUuid;
  final List<dynamic> selectedInvoices;
  final int selectedInvoiceIndex;

  final ValueChanged<int> onInvoiceIndexChanged;
  final ValueChanged<String> onInvoiceDeleted;
  final ValueChanged<List<String>> onInvoiceFilesDropped;

  const InvoicePdfPanel({
    super.key,
    required this.selectedExpenseUuid,
    required this.selectedInvoices,
    required this.selectedInvoiceIndex,
    required this.onInvoiceIndexChanged,
    required this.onInvoiceDeleted,
    required this.onInvoiceFilesDropped,
  });

  @override
  State<InvoicePdfPanel> createState() => _InvoicePdfPanelState();
}

class _InvoicePdfPanelState extends State<InvoicePdfPanel> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    // 计算当前可预览的 PDF 路径
    String? previewPath;
    if (widget.selectedInvoices.isNotEmpty &&
        widget.selectedInvoiceIndex >= 0 &&
        widget.selectedInvoiceIndex < widget.selectedInvoices.length) {
      previewPath = widget.selectedInvoices[widget.selectedInvoiceIndex]
              ['saved_path']
          as String?;
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          // ── 发票缩略图条 ──
          if (widget.selectedInvoices.isNotEmpty &&
              widget.selectedInvoiceIndex >= 0)
            _buildThumbnailStrip(),
          // ── PDF 内容区 / 拖拽目标 ──
          Expanded(child: _buildPdfArea(previewPath)),
        ],
      ),
    );
  }

  /// 发票缩略图横向滚动条
  Widget _buildThumbnailStrip() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.06),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: widget.selectedInvoices.length,
        separatorBuilder: (_, _) =>
            const VerticalDivider(width: 1, color: Colors.black12),
        itemBuilder: (ctx, i) {
          final inv = widget.selectedInvoices[i];
          final isActive = i == widget.selectedInvoiceIndex;
          return InkWell(
            onTap: () => widget.onInvoiceIndexChanged(i),
            child: Container(
              color: isActive
                  ? Colors.blue.withValues(alpha: 0.1)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf,
                      size: 16,
                      color: isActive ? Colors.blue : Colors.red),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      inv['file_name']?.toString() ?? '未知',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    color: Colors.redAccent,
                    tooltip: '解绑删除',
                    onPressed: () =>
                        widget.onInvoiceDeleted(inv['uuuid']),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// PDF 渲染区 + DropTarget
  Widget _buildPdfArea(String? previewPath) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        // 过滤出所有 PDF 文件
        final pdfPaths = details.files
            .where((f) => f.path.toLowerCase().endsWith('.pdf'))
            .map((f) => f.path)
            .toList();
        if (pdfPaths.isEmpty) {
          _showSnack('未检测到 PDF 文件，请拖入 .pdf 格式发票！', isError: true);
          return;
        }
        widget.onInvoiceFilesDropped(pdfPaths);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isDragging
              ? Colors.blue.withValues(alpha: 0.15)
              : const Color(0xFF525659).withValues(alpha: 0.08),
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(12)),
          border: _isDragging
              ? Border.all(color: Colors.blue, width: 2)
              : null,
        ),
        child: previewPath != null
            ? ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12)),
                child: SfPdfViewer.file(File(previewPath)),
              )
            : _buildEmptyState(),
      ),
    );
  }

  /// 空状态 / 拖拽提示
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.picture_as_pdf_outlined,
            size: 64,
            color: _isDragging ? Colors.blue : Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            widget.selectedExpenseUuid == null
                ? '请点击左侧列表查看发票原件'
                : '将 PDF 发票拖拽到此处绑定',
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500),
          ),
          if (widget.selectedExpenseUuid != null) ...[
            const SizedBox(height: 8),
            Text('（支持 .pdf 格式文件）',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ],
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}
