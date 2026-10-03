import 'package:material_ui/material_ui.dart';

/// GitHub 风格年度热力格子:列=周(约53列),行=星期(7行),
/// 格子颜色深浅表示当日计数。支持「观看 / 收藏」双数据源切换。
class HeatmapCard extends StatefulWidget {
  const HeatmapCard({
    super.key,
    required this.colorScheme,
    required this.watchCounts,
    required this.favCounts,
    required this.year,
  });

  final ColorScheme colorScheme;

  /// 当年每日观看次数:yyyyMMdd → 次数
  final Map<int, int> watchCounts;

  /// 当年每日收藏次数:yyyyMMdd → 次数
  final Map<int, int> favCounts;

  /// 展示年份(全年视图)
  final int year;

  @override
  State<HeatmapCard> createState() => _HeatmapCardState();
}

class _HeatmapCardState extends State<HeatmapCard> {
  /// 0=观看 1=收藏
  int _mode = 0;

  Map<int, int> get _counts =>
      _mode == 0 ? widget.watchCounts : widget.favCounts;

  static const int _cellSize = 15;
  static const double _spacing = 3;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    // 该年 1月1日 的星期(周一=1),决定首列前置空格数
    final firstDate = DateTime(widget.year, 1, 1);
    final firstWeekday = firstDate.weekday; // 1=周一..7=周日
    final leadEmpty = firstWeekday - 1;

    // 总格子数(含前置空格),按 7 行折算列数
    final daysInYear = DateTime(
      widget.year + 1,
      1,
      1,
    ).difference(firstDate).inDays;
    final totalCells = leadEmpty + daysInYear;
    final weeks = (totalCells / 7).ceil();

    final monthLabels = _monthLabels(leadEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              Text(
                '活跃热力图',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              _modeChip(context, '观看', 0),
              const SizedBox(width: 6),
              _modeChip(context, '收藏', 1),
            ],
          ),
          Text(
            '${widget.year} 年 · 每格一天,颜色越深代表当日'
            '${_mode == 0 ? '观看' : '收藏'}越多;点击格子查看当日明细。',
            style: TextStyle(fontSize: 11, color: colorScheme.outline),
          ),
          // 月份标签行(与格子横向滚动对齐)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: weeks * (_cellSize + _spacing),
              child: Row(
                children: [
                  for (final label in _monthLabels(leadEmpty))
                    SizedBox(
                      width: label.width.toDouble(),
                      child: Text(
                        label.text,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 格子区:横向滚动,每列一周(周一~周日)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: weeks * (_cellSize + _spacing),
              height: 7 * (_cellSize + _spacing) - _spacing,
              child: GridView.count(
                crossAxisCount: 7,
                scrollDirection: Axis.horizontal,
                mainAxisSpacing: _spacing,
                crossAxisSpacing: _spacing,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  for (int i = 0; i < leadEmpty; i++) const SizedBox.shrink(),
                  for (int dayOfYear = 0; dayOfYear < daysInYear; dayOfYear++)
                    _buildCell(context, dayOfYear),
                ],
              ),
            ),
          ),
          // 图例
          Row(
            children: [
              Text(
                '少',
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
              const SizedBox(width: 4),
              for (final intensity in [0, 1, 2, 3, 4])
                Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: _cellColor(context, intensity),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                '多',
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
              const Spacer(),
              Text(
                _mode == 0 ? '当日观看次数' : '当日收藏次数',
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 每月标签:宽度按该月天数折算;首月计入年份首日的前置空格。
  List<({String text, double width})> _monthLabels(int leadEmpty) {
    final labels = <({String text, double width})>[];
    for (int month = 1; month <= 12; month++) {
      final daysInMonth =
          DateTime(
            widget.year,
            month + 1,
            0,
          ).difference(DateTime(widget.year, month, 1)).inDays +
          1;
      var width = daysInMonth * (_cellSize + _spacing);
      if (month == 1) width += leadEmpty * (_cellSize + _spacing);
      labels.add((text: '$month月', width: width));
    }
    return labels;
  }

  Color _cellColor(BuildContext context, int intensity) {
    final primary = widget.colorScheme.primary;
    return switch (intensity) {
      0 => widget.colorScheme.onSurface.withValues(alpha: 0.06),
      1 => primary.withValues(alpha: 0.25),
      2 => primary.withValues(alpha: 0.45),
      3 => primary.withValues(alpha: 0.7),
      _ => primary,
    };
  }

  int _intensityFor(int count) => switch (count) {
    0 => 0,
    1 => 1,
    2 || 3 => 2,
    4 || 5 || 6 => 3,
    _ => 4,
  };

  Widget _buildCell(BuildContext context, int dayOfYear) {
    final date = DateTime(widget.year, 1, 1 + dayOfYear);
    final key = date.year * 10000 + date.month * 100 + date.day;
    final count = _counts[key] ?? 0;
    final intensity = _intensityFor(count);
    return GestureDetector(
      onTap: count > 0
          ? () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}:'
                  '${_mode == 0 ? '观看' : '收藏'} $count 次',
                ),
                duration: const Duration(milliseconds: 1500),
              ),
            )
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: _cellColor(context, intensity),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Widget _modeChip(BuildContext context, String text, int mode) {
    final colorScheme = widget.colorScheme;
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.secondaryContainer
              : colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : null,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
