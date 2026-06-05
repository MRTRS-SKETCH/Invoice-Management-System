import 'package:flutter/material.dart';
import '../../../widgets/glass_card.dart';

/// 开销频次热力图卡片 — 横向滚动 + 自适应行数 + 默认展示最新日期
///
/// 按日聚合的开销记录数映射为五级色阶。
/// 根据可用高度动态调整行数，默认滚动到最新日期列。
class HeatmapCard extends StatefulWidget {
  final List<dynamic> heatmap;

  const HeatmapCard({super.key, required this.heatmap});

  @override
  State<HeatmapCard> createState() => _HeatmapCardState();
}

class _HeatmapCardState extends State<HeatmapCard> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _didInitialScroll = false;
  double _lastGridWidth = 0;
  bool _callbackScheduled = false;

  @override
  void didUpdateWidget(covariant HeatmapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heatmap != widget.heatmap) {
      _didInitialScroll = false;
    }
  }

  /// 布局稳定后滚动到最新日期（右侧）；容器宽度变化时也重新滚动
  void _tryScrollToLatest({double gridWidth = 0}) {
    if (!_scrollCtrl.hasClients) return;
    if (_didInitialScroll && (gridWidth - _lastGridWidth).abs() < 10) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return; // 内容尚未撑开
    _didInitialScroll = true;
    _lastGridWidth = gridWidth;
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (_scrollCtrl.hasClients && mounted) {
        _scrollCtrl.jumpTo(max);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '业务发生频次',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.heatmap.isEmpty
                ? const Center(
                    child: Text('暂无数据',
                        style: TextStyle(color: Colors.black38)))
                : LayoutBuilder(
                    builder: (ctx, constraints) {
                      // 固定 3 行
                      const rows = 3;
                      const spacing = 4.0;
                      final cellSize =
                          (constraints.maxHeight - (rows - 1) * spacing) / rows;
                      final columns =
                          (widget.heatmap.length / rows).ceil();
                      final gridWidth = columns * cellSize +
                          (columns - 1) * spacing;
                      final fitsInView = gridWidth < constraints.maxWidth;

                      // 每次布局时尝试滚动到最新（右侧），用 guard 防重复注册
                      if (!_callbackScheduled) {
                        _callbackScheduled = true;
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) {
                          _callbackScheduled = false;
                          _tryScrollToLatest(gridWidth: gridWidth);
                        });
                      }

                      final grid = RepaintBoundary(
                        child: GridView.builder(
                          controller: _scrollCtrl,
                          scrollDirection: Axis.horizontal,
                          physics: fitsInView
                              ? const NeverScrollableScrollPhysics()
                              : const BouncingScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: rows,
                            childAspectRatio: 1,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                          ),
                          itemCount: widget.heatmap.length,
                          itemBuilder: (ctx, i) {
                            final count =
                                (widget.heatmap[i]['count'] as int?) ?? 0;
                            final Color bg;
                            if (count == 0) {
                              bg = const Color(0xFFE2E8F0);
                            } else if (count <= 1) {
                              bg = const Color(0xFFC7D2FE);
                            } else if (count <= 3) {
                              bg = const Color(0xFF818CF8);
                            } else if (count <= 6) {
                              bg = const Color(0xFF4F46E5);
                            } else {
                              bg = const Color(0xFF312E81);
                            }
                            return _HeatmapCell(
                              tooltip:
                                  '${widget.heatmap[i]['date']}: $count 笔',
                              color: bg,
                            );
                          },
                        ),
                      );

                      // 内容不足时右对齐，否则正常滚动
                      if (fitsInView) {
                        return Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: gridWidth,
                            height: constraints.maxHeight,
                            child: grid,
                          ),
                        );
                      }
                      return grid;
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
/// 热力图单元格 — 轻量 hover 样式（无 AnimatedContainer，无 transform，避免 layout 抖动）
// ═══════════════════════════════════════════════════════════════════════════════
class _HeatmapCell extends StatefulWidget {
  final Color color;
  final String tooltip;
  const _HeatmapCell({required this.color, required this.tooltip});

  @override
  State<_HeatmapCell> createState() => _HeatmapCellState();
}

class _HeatmapCellState extends State<_HeatmapCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(_isHovered ? 4 : 2),
            border: _isHovered
                ? Border.all(color: Colors.white, width: 2)
                : null,
            boxShadow: _isHovered
                ? [const BoxShadow(
                    color: Colors.black26, blurRadius: 4, spreadRadius: 1)]
                : [],
          ),
        ),
      ),
    );
  }
}
