import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/expense_service.dart';
import '../main.dart' show restartBackend;

/// 路径设置对话框 — 用户可在标题栏齿轮图标打开，选择数据库/日志存放目录
///
/// - 数据库路径：可浏览选择，下方实时显示将创建的子目录结构
/// - 日志路径：可浏览选择（不允许放在 PDF 目录内）
/// - PDF 路径：只读展示，自动跟随 `{db_path}/pdfs/`
/// - 底部：保存按钮 + 重新连接并重启按钮
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _dbController = TextEditingController();
  final _logController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _restarting = false;
  String? _error;

  // 当前实际配置（从后端加载）
  String? _currentDbPath;
  String? _currentLogPath;

  // 实时预览结构
  List<String> _dbPreview = [];
  List<String> _logPreview = [];
  String _previewPdfPath = '—';

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
    _dbController.addListener(_onPathChanged);
    _logController.addListener(_onPathChanged);
  }

  @override
  void dispose() {
    _dbController.removeListener(_onPathChanged);
    _logController.removeListener(_onPathChanged);
    _dbController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentConfig() async {
    try {
      final cfg = await ExpenseService.fetchSettingsPaths();
      _currentDbPath = cfg['db_path'] as String? ?? '';
      _currentLogPath = cfg['log_path'] as String? ?? '';
      _dbController.text = _currentDbPath!;
      _logController.text = _currentLogPath!;
      _error = null;
      // 加载初始预览
      _updatePreview();
    } catch (e) {
      _error = '无法加载当前配置: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onPathChanged() {
    _updatePreview();
  }

  /// 防抖：用户输入 400ms 后刷新预览
  Future<void> _updatePreview() async {
    final db = _dbController.text.trim();
    final log = _logController.text.trim();
    if (db.isEmpty || log.isEmpty) {
      setState(() {
        _dbPreview = [];
        _logPreview = [];
        _previewPdfPath = db.isEmpty ? '—' : '$db/pdfs/';
      });
      return;
    }
    try {
      final preview = await ExpenseService.previewPaths(db, log);
      if (mounted) {
        setState(() {
          _dbPreview = (preview['db_structure'] as List?)?.cast<String>() ?? [];
          _logPreview = (preview['log_structure'] as List?)?.cast<String>() ?? [];
          _previewPdfPath = preview['pdf_path'] as String? ?? _previewPdfPath;
        });
      }
    } catch (_) {
      // 后端不可用时用本地推算
      if (mounted) {
        setState(() {
          _dbPreview = ['invoice_system.db', 'invoice_system.db-wal', 'invoice_system.db-shm', 'pdfs/'];
          _logPreview = ['app.log'];
          _previewPdfPath = '$db${db.endsWith('/') || db.endsWith('\\') ? '' : '/'}pdfs/';
        });
      }
    }
  }

  Future<void> _pickDirectory(TextEditingController controller) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      controller.text = result;
      // _onPathChanged 会自动触发预览刷新
    }
  }

  Future<void> _save() async {
    final dbPath = _dbController.text.trim();
    final logPath = _logController.text.trim();

    if (dbPath.isEmpty || logPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据库路径和日志路径不能为空')),
        );
      }
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      await ExpenseService.updateSettingsPaths(dbPath, logPath);
      _currentDbPath = dbPath;
      _currentLogPath = logPath;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 设置已保存，目录结构已创建。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      final msg = e.toString();
      setState(() => _error = msg.startsWith('Exception: ') ? msg.substring(11) : msg);
    }

    if (mounted) setState(() => _saving = false);
  }

  Future<void> _reconnect() async {
    // 先确认
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新连接并重启'),
        content: const Text('将使用新配置重启后端服务引擎。\n\n前端页面会短暂显示加载状态，请稍候。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认重启')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _restarting = true;
      _error = null;
    });

    try {
      // 先发重启信号（后端确认）
      await ExpenseService.requestRestart();

      // 关闭对话框，让用户看到加载状态
      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('正在重启后端引擎...'),
              ],
            ),
            duration: Duration(seconds: 20),
          ),
        );
      }

      final ok = await restartBackend();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '✅ 后端已重新连接，新配置已生效。' : '⚠️ 后端启动超时，请手动重启应用。'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _restarting = false;
          _error = '重启失败: ${msg.startsWith("Exception: ") ? msg.substring(11) : msg}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smallStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 11);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings, size: 20),
          SizedBox(width: 8),
          Text('路径设置', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
                    ),

                  // ── 数据库路径 ──
                  _PathRow(
                    label: '数据库路径',
                    hint: 'invoice_system.db 存放目录',
                    controller: _dbController,
                    onPick: () => _pickDirectory(_dbController),
                  ),
                  if (_dbPreview.isNotEmpty) _buildPreviewTree(_dbPreview, _dbController.text.trim()),

                  const SizedBox(height: 14),

                  // ── 日志路径 ──
                  _PathRow(
                    label: '日志路径',
                    hint: 'app.log 存放目录',
                    controller: _logController,
                    onPick: () => _pickDirectory(_logController),
                  ),
                  if (_logPreview.isNotEmpty) _buildPreviewTree(_logPreview, _logController.text.trim()),

                  const SizedBox(height: 14),

                  // ── PDF 路径（只读预览）──
                  Text('PDF 路径', style: smallStyle?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf, size: 14, color: Colors.red.shade300),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _previewPdfPath,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  Text(
                    '💡 保存后目录结构会立即创建；重启后端后新路径完全生效。',
                    style: smallStyle?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        // 左侧：重新连接
        TextButton.icon(
          onPressed: _restarting ? null : _reconnect,
          icon: _restarting
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, size: 16),
          label: const Text('重新连接'),
        ),
        // 右侧：取消 + 保存
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: (_saving || _restarting) ? null : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: (_saving || _restarting) ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建目录结构预览树（灰色小字 + 缩进图标）
  Widget _buildPreviewTree(List<String> items, String rootDir) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 根目录
          Row(
            children: [
              Icon(Icons.folder, size: 13, color: Colors.amber.shade600),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  rootDir,
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // 子项
          ...items.map((item) {
            final isDir = item.endsWith('/');
            return Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  Icon(
                    isDir ? Icons.folder : Icons.insert_drive_file,
                    size: 12,
                    color: isDir ? Colors.amber.shade500 : Colors.blueGrey.shade300,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item,
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 单行路径选择控件 — 标签 + 输入框 + 浏览按钮
class _PathRow extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onPick;

  const _PathRow({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(fontSize: 11),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: onPick,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: const Text('浏览', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
