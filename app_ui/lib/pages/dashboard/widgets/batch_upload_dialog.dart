import 'package:flutter/material.dart';

/// 毛玻璃遮罩 + 进度提示，防止批量解析期间用户误操作。
/// 显示「正在智能解析发票...」并带圆形进度条。
class BatchUploadDialog extends StatelessWidget {
  final int total;
  const BatchUploadDialog({super.key, required this.total});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                '正在智能解析发票...',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '共 $total 张，请勿关闭窗口',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}


/// 批量建档前 — 开销项目 / 开销类型 配置表单
class BatchInfoDialog extends StatefulWidget {
  final List<String> existingProjects;
  final List<String> existingTypes;
  const BatchInfoDialog({
    super.key,
    required this.existingProjects,
    required this.existingTypes,
  });

  @override
  State<BatchInfoDialog> createState() => _BatchInfoDialogState();
}

class _BatchInfoDialogState extends State<BatchInfoDialog> {
  final _projectCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();

  @override
  void dispose() {
    _projectCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
          width: 400,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(Icons.tune, size: 20, color: Colors.indigo.shade600),
                const SizedBox(width: 8),
                const Text('批量建档配置',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Text(
                '以下信息将应用到本次导入的所有发票',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              _buildAutocomplete(
                '开销项目',
                Icons.folder_outlined,
                _projectCtrl,
                widget.existingProjects,
              ),
              const SizedBox(height: 14),
              _buildAutocomplete(
                '开销类型',
                Icons.category_outlined,
                _typeCtrl,
                widget.existingTypes,
                hint: '如：差旅交通 / 云服务采购',
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('跳过',
                        style: TextStyle(color: Colors.black54)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop({
                        'project_name': _projectCtrl.text.trim(),
                        'expense_type': _typeCtrl.text.trim(),
                      });
                    },
                    child: const Text('开始导入'),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildAutocomplete(
    String label,
    IconData icon,
    TextEditingController ctrl,
    List<String> options, {
    String? hint,
  }) {
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
            prefixIcon: Icon(icon, size: 20),
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}
