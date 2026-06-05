import 'package:flutter/material.dart';
import '../../../services/expense_service.dart';

/// 新增业务开销记录的独立 Dialog 组件
///
/// 从 [ExpenseTablePanel] 中抽取，管理自身的表单状态和控制器。
class AddExpenseDialog extends StatefulWidget {
  final List<String> existingProjects;
  final List<String> existingTypes;

  /// 新增成功后通知父级刷新
  final VoidCallback onSubmitted;

  const AddExpenseDialog({
    super.key,
    required this.existingProjects,
    required this.existingTypes,
    required this.onSubmitted,
  });

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _projectCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _dateCtrl.dispose();
    _projectCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  void _clearForm() {
    _titleCtrl.clear();
    _amountCtrl.clear();
    _dateCtrl.clear();
    _projectCtrl.clear();
    _typeCtrl.clear();
  }

  Future<void> _submitAddExpense(BuildContext dialogCtx) async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await ExpenseService.addExpense({
        'title': _titleCtrl.text.trim(),
        'amount': double.parse(_amountCtrl.text.trim()),
        'incurred_date': _dateCtrl.text.trim(),
        'status': '待开票',
        'project_name':
            _projectCtrl.text.trim().isEmpty ? null : _projectCtrl.text.trim(),
        'expense_type':
            _typeCtrl.text.trim().isEmpty ? null : _typeCtrl.text.trim(),
      });
      _clearForm();
      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
      widget.onSubmitted();
    } catch (e) {
      if (dialogCtx.mounted) {
        ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
          content: Text('新增失败: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  Widget _field(String label, IconData icon, TextEditingController ctrl,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration:
          InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: validator,
    );
  }

  Widget _autocompleteField(
      String label, IconData icon, TextEditingController ctrl,
      {required List<String> options, String? hint}) {
    return Autocomplete<String>(
      optionsBuilder: (v) {
        if (v.text.isEmpty) return options;
        return options
            .where((o) => o.toLowerCase().contains(v.text.toLowerCase()));
      },
      onSelected: (val) => ctrl.text = val,
      fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
        controller.text = ctrl.text;
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (v) => ctrl.text = v,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            hintText: hint,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _clearForm();
    return AlertDialog(
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      title: const Text('新增业务开销记录',
          style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('事由 / 开销名称 *', Icons.edit_note, _titleCtrl,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入事由' : null),
              const SizedBox(height: 14),
              _field('金额 (元) *', Icons.attach_money, _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入金额';
                    if (double.tryParse(v.trim()) == null) return '请输入合法数字';
                    return null;
                  }),
              const SizedBox(height: 14),
              TextFormField(
                controller: _dateCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                    labelText: '发生日期 *',
                    prefixIcon: Icon(Icons.calendar_today)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2101),
                  );
                  if (picked != null) {
                    _dateCtrl.text =
                        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                  }
                },
                validator: (v) =>
                    (v == null || v.isEmpty) ? '请选择日期' : null,
              ),
              const SizedBox(height: 14),
              _autocompleteField(
                  '开销项目', Icons.folder_outlined, _projectCtrl,
                  options: widget.existingProjects),
              const SizedBox(height: 14),
              _autocompleteField(
                  '开销类型', Icons.category_outlined, _typeCtrl,
                  options: widget.existingTypes,
                  hint: '选择或输入类型（如差旅交通）'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          onPressed: () => _submitAddExpense(context),
          child: const Text('提交保存',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
