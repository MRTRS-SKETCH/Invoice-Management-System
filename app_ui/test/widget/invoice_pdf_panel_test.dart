import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_ui/pages/dashboard/widgets/invoice_pdf_panel.dart';
import '../helpers/test_helper.dart';

void main() {
  setUpAll(() => initTestEnvironment());

  // Note: 发票数据中的 saved_path 设为 null，避免 SfPdfViewer.file() 尝试加载
  // 不存在的 PDF 文件导致测试崩溃。缩略图条和回调逻辑不受影响。

  group('InvoicePdfPanel', () {
    // ── Happy Path ──
    testWidgets('无选中条目时应显示"请点击左侧列表查看发票原件"', (tester) async {
      // Arrange
      final panel = InvoicePdfPanel(
        selectedExpenseUuid: null,
        selectedInvoices: [],
        selectedInvoiceIndex: -1,
        onInvoiceIndexChanged: (_) {},
        onInvoiceDeleted: (_) {},
        onInvoiceFilesDropped: (_) {},
      );

      // Act
      await pumpTestWidget(tester, panel);

      // Assert
      expect(find.text('请点击左侧列表查看发票原件'), findsOneWidget);
    });

    testWidgets('有选中条目但无发票时应显示拖拽提示', (tester) async {
      // Arrange
      final panel = InvoicePdfPanel(
        selectedExpenseUuid: 'exp-test',
        selectedInvoices: [],
        selectedInvoiceIndex: -1,
        onInvoiceIndexChanged: (_) {},
        onInvoiceDeleted: (_) {},
        onInvoiceFilesDropped: (_) {},
      );

      // Act
      await pumpTestWidget(tester, panel);

      // Assert
      expect(find.text('将 PDF 发票拖拽到此处绑定'), findsOneWidget);
      expect(find.textContaining('.pdf'), findsOneWidget);
    });

    // ── Boundary ──
    testWidgets('发票索引为负数不应崩溃', (tester) async {
      // Arrange
      final panel = InvoicePdfPanel(
        selectedExpenseUuid: 'exp-test',
        selectedInvoices: [],
        selectedInvoiceIndex: -5,
        onInvoiceIndexChanged: (_) {},
        onInvoiceDeleted: (_) {},
        onInvoiceFilesDropped: (_) {},
      );

      // Act
      await pumpTestWidget(tester, panel);

      // Assert
      expect(tester.takeException(), isNull);
    });

    testWidgets('发票索引越界不应崩溃', (tester) async {
      // Arrange
      final invoices = [
        {'uuuid': 'inv-1', 'file_name': 'f1.pdf', 'saved_path': null},
      ];

      await pumpTestWidget(
        tester,
        InvoicePdfPanel(
          selectedExpenseUuid: 'exp-test',
          selectedInvoices: invoices,
          selectedInvoiceIndex: 99, // 越界
          onInvoiceIndexChanged: (_) {},
          onInvoiceDeleted: (_) {},
          onInvoiceFilesDropped: (_) {},
        ),
      );

      // Assert
      expect(tester.takeException(), isNull);
    });

    // ── 缩略图条渲染（saved_path 为 null 避免 PDF 加载） ──
    testWidgets('有发票数据时应显示缩略图条中的文件名', (tester) async {
      // Arrange — 使用 null saved_path 避免 SfPdfViewer 加载
      final invoices = [
        {'uuuid': 'inv-1', 'file_name': '测试发票001.pdf', 'saved_path': null},
      ];

      await pumpTestWidget(
        tester,
        InvoicePdfPanel(
          selectedExpenseUuid: 'exp-test',
          selectedInvoices: invoices,
          selectedInvoiceIndex: 0,
          onInvoiceIndexChanged: (_) {},
          onInvoiceDeleted: (_) {},
          onInvoiceFilesDropped: (_) {},
        ),
      );

      // Assert — 缩略图条中文件名可见
      expect(find.text('测试发票001.pdf'), findsOneWidget);
    });

    testWidgets('多张发票时缩略图条包含所有文件名', (tester) async {
      // Arrange
      final invoices = [
        {'uuuid': 'inv-a', 'file_name': '发票A.pdf', 'saved_path': null},
        {'uuuid': 'inv-b', 'file_name': '发票B.pdf', 'saved_path': null},
        {'uuuid': 'inv-c', 'file_name': '发票C.pdf', 'saved_path': null},
      ];

      await pumpTestWidget(
        tester,
        InvoicePdfPanel(
          selectedExpenseUuid: 'exp-test',
          selectedInvoices: invoices,
          selectedInvoiceIndex: 0,
          onInvoiceIndexChanged: (_) {},
          onInvoiceDeleted: (_) {},
          onInvoiceFilesDropped: (_) {},
        ),
      );

      // Assert
      expect(find.text('发票A.pdf'), findsOneWidget);
      expect(find.text('发票B.pdf'), findsOneWidget);
      expect(find.text('发票C.pdf'), findsOneWidget);
    });

    // ── 回调验证 ──
    testWidgets('点击缩略图应触发 onInvoiceIndexChanged', (tester) async {
      // Arrange
      int? changedIndex;
      final invoices = [
        {'uuuid': 'inv-1', 'file_name': '发票1.pdf', 'saved_path': null},
        {'uuuid': 'inv-2', 'file_name': '发票2.pdf', 'saved_path': null},
      ];

      await pumpTestWidget(
        tester,
        InvoicePdfPanel(
          selectedExpenseUuid: 'exp-test',
          selectedInvoices: invoices,
          selectedInvoiceIndex: 0,
          onInvoiceIndexChanged: (i) => changedIndex = i,
          onInvoiceDeleted: (_) {},
          onInvoiceFilesDropped: (_) {},
        ),
      );

      // Act — 点击第二个缩略图
      await tester.tap(find.text('发票2.pdf'));
      await tester.pump();

      // Assert
      expect(changedIndex, 1);
    });

    testWidgets('点击删除按钮应触发 onInvoiceDeleted', (tester) async {
      // Arrange
      String? deletedUuid;
      final invoices = [
        {'uuuid': 'inv-del', 'file_name': '待删发票.pdf', 'saved_path': null},
      ];

      await pumpTestWidget(
        tester,
        InvoicePdfPanel(
          selectedExpenseUuid: 'exp-test',
          selectedInvoices: invoices,
          selectedInvoiceIndex: 0,
          onInvoiceIndexChanged: (_) {},
          onInvoiceDeleted: (id) => deletedUuid = id,
          onInvoiceFilesDropped: (_) {},
        ),
      );

      // Act — 点击关闭 (Icons.close) 按钮
      final closeBtn = find.byIcon(Icons.close);
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();

      // Assert
      expect(deletedUuid, 'inv-del');
    });
  });
}
