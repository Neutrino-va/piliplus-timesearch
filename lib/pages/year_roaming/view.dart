import 'dart:math' as math;

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/pages/year_recall/controller.dart';
import 'package:PiliPlus/pages/year_recall/view.dart';
import 'package:PiliPlus/pages/year_roaming/controller.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class YearRoamingPage extends StatefulWidget {
  const YearRoamingPage({super.key});

  @override
  State<YearRoamingPage> createState() => _YearRoamingPageState();
}

class _YearRoamingPageState extends State<YearRoamingPage>
    with AutomaticKeepAliveClientMixin {
  final _controller = Get.putOrFind(YearRoamingController.new);
  // 页面自持滚动控制器：底部 tab 与独立路由两个入口共享同一个
  // YearRoamingController，不能再共用其 scrollController（存在双 attach
  // 与 GetX 回收后 dispose 复用的风险）。
  final ScrollController _scrollController = ScrollController();

  /// 「年份回顾」控制器懒创建：首次切到该模式时才实例化并发起请求。
  YearRecallController? _recallController;

  YearRecallController? get _recall {
    if (!_controller.recallMode.value) return null;
    // putOrFind 与其他入口共享实例，避免重复创建。
    final controller = _recallController ??= Get.putOrFind(
      YearRecallController.new,
    );
    return controller;
  }

  void _setRecallMode(bool value) {
    if (_controller.recallMode.value == value) return;
    _controller.recallMode.value = value;
    if (value) {
      _recall;
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(
      () {
        final theme = Theme.of(context);
        final state = _controller.loadingState.value;
        return SimpleScaffold(
          appBar: AppBar(
            title: const Text('年份漫游'),
            actions: [
              IconButton(
                tooltip: '刷新年度数据',
                onPressed: _controller.onRefresh,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildModeSwitch(theme)),
              if (_recall case final recallController?) ...[
                ...YearRecallView.buildSlivers(theme, recallController),
              ] else ...[
                SliverToBoxAdapter(child: _buildYearPicker(theme)),
                ...switch (state) {
                  Loading() => [_buildLoading(theme)],
                  Success<List<HistoryItemModel>?>(:final response) =>
                    response == null || response.isEmpty
                        ? [_buildEmpty(theme)]
                        : _buildContent(theme, response),
                  Error(:final errMsg) => [
                    HttpError(
                      errMsg: errMsg,
                      onReload: _controller.onReload,
                    ),
                  ],
                },
              ],
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40 + MediaQuery.viewPaddingOf(context).bottom,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 顶部模式切换：「我的回顾」（按观看时间）/「年份回顾」（按发布年份）。
  Widget _buildModeSwitch(ThemeData theme) {
    final recall = _controller.recallMode.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        spacing: 8,
        children: [
          SearchText(
            text: '我的回顾',
            bgColor: !recall ? theme.colorScheme.secondaryContainer : null,
            textColor: !recall
                ? theme.colorScheme.onSecondaryContainer
                : null,
            onTap: (_) => _setRecallMode(false),
          ),
          SearchText(
            text: '年份回顾',
            bgColor: recall ? theme.colorScheme.secondaryContainer : null,
            textColor: recall
                ? theme.colorScheme.onSecondaryContainer
                : null,
            onTap: (_) => _setRecallMode(true),
          ),
        ],
      ),
    );
  }

  Widget _buildYearPicker(ThemeData theme) {
    final rangeStart = _controller.rangeStart.value;
    final rangeEnd = _controller.rangeEnd.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '选择回顾范围',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  '${DateFormatUtils.longFormat.format(rangeStart)} - '
                  '${DateFormatUtils.longFormat.format(rangeEnd)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: _controller.availableYears
                  .map(
                    (year) => SearchText(
                      text: '$year',
                      onTap: (_) => _controller.selectYear(year),
                      bgColor: _controller.isYearSelected(year)
                          ? theme.colorScheme.secondaryContainer
                          : null,
                      textColor: _controller.isYearSelected(year)
                          ? theme.colorScheme.onSecondaryContainer
                          : null,
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: _DateRangeButton(
                  date: rangeStart,
                  label: '开始日期',
                  enabled: _controller.isCustomRange,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              Text('至', style: TextStyle(color: theme.colorScheme.outline)),
              Expanded(
                child: _DateRangeButton(
                  date: rangeEnd,
                  label: '结束日期',
                  enabled: _controller.isCustomRange,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '统计口径：按该范围内的观看记录计算；“最喜欢”指范围内看过且当前仍在收藏夹中的内容。',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final start = _controller.rangeStart.value;
    final end = _controller.rangeEnd.value;
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? start : end,
      firstDate: isStart ? _controller.pickerFirstDate : start,
      lastDate: isStart ? end : _controller.latestDate,
      helpText: isStart ? '选择开始日期' : '选择结束日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) return;

    if (isStart) {
      _controller.selectRange(picked, end);
    } else {
      _controller.selectRange(start, picked);
    }
  }

  SliverToBoxAdapter _buildLoading(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                '正在整理该年度观看记录…',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildEmpty(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 64, 24, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '这一年还没有可回顾的观看记录',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '可以切换其他年份，或先登录账号并积累一些观看记录。',
              style: TextStyle(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent(
    ThemeData theme,
    List<HistoryItemModel> records,
  ) {
    final highlight = _controller.highlightItem;
    return [
      SliverToBoxAdapter(child: _buildSummary(theme, records, highlight)),
      SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        sliver: SliverList.builder(
          itemBuilder: (context, index) => _YearHistoryItem(
            item: records[index],
            onTap: () => _openHistoryItem(records[index]),
          ),
          itemCount: records.length,
        ),
      ),
    ];
  }

  Widget _buildSummary(
    ThemeData theme,
    List<HistoryItemModel> records,
    HistoryItemModel? highlight,
  ) {
    final primaryContainer = theme.colorScheme.primaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryContainer,
                  primaryContainer.withValues(alpha: 0.45),
                ],
              ),
              borderRadius: Style.mdRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_controller.selectedYear.value} · 我的年度回顾',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _controller.rangeDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '这一年，你在 PiliPlus 留下了 ${records.length} 条观看足迹。',
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatTile(
                      icon: Icons.play_circle_outline,
                      label: '看过内容',
                      value: '${_controller.watchedCount.value}',
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    _StatTile(
                      icon: Icons.schedule_outlined,
                      label: '观看时长',
                      value: _controller.formatWatchDuration(),
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    _StatTile(
                      icon: Icons.check_circle_outline,
                      label: '看完内容',
                      value: '${_controller.completedCount.value}',
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    _StatTile(
                      icon: Icons.favorite_border,
                      label: '仍在收藏',
                      value: '${_controller.favoriteCount.value}',
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildInsight(theme),
          if (highlight != null) ...[
            const SizedBox(height: 10),
            _buildHighlight(theme, highlight),
          ],
          const SizedBox(height: 12),
          Text(
            '这一年的观看内容',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsight(ThemeData theme) {
    final author = _controller.mostWatchedAuthor.value;
    final tag = _controller.mostWatchedTag.value;
    final children = <Widget>[];
    if (author.isNotEmpty) {
      children.add(
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '最常观看的 UP 主：'),
              TextSpan(
                text: '$author（${_controller.mostWatchedAuthorCount.value} 条）',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (tag.isNotEmpty) {
      children.add(
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '最常出现的分区：'),
              TextSpan(
                text: '$tag（${_controller.mostWatchedTagCount.value} 条）',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: Style.mdRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: children,
      ),
    );
  }

  Widget _buildHighlight(ThemeData theme, HistoryItemModel item) {
    final cover = item.cover?.isNotEmpty == true
        ? item.cover
        : item.covers?.isNotEmpty == true
        ? item.covers!.first
        : '';
    return Material(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () => _openHistoryItem(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NetworkImgLayer(
                width: 136,
                height: 84,
                src: cover,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '年度最喜欢',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title ?? '未命名内容',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.authorName?.isNotEmpty == true
                          ? item.authorName!
                          : '未知 UP 主',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    PBadge(
                      text: item.isFav == 1 ? '当前已收藏' : '观看时长最高',
                      type: PBadgeType.gray,
                      // PBadge 默认 isStack:true 会返回 Positioned，
                      // 只能放在 Stack 里；此处父级是 Column，必须关闭。
                      isStack: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openHistoryItem(HistoryItemModel item) async {
    final business = item.history.business;
    if (business?.contains('article') == true) {
      PageUtils.toDupNamed(
        '/articlePage',
        parameters: {
          'id': business == 'article-list'
              ? '${item.history.cid}'
              : '${item.history.oid}',
          'type': 'read',
        },
      );
      return;
    }
    if (business == 'live') {
      if (item.liveStatus == 1) {
        PageUtils.toLiveRoom(item.history.oid);
      } else {
        SmartDialog.showToast('直播未开播');
      }
      return;
    }
    if (business == 'pgc') {
      PageUtils.viewPgc(
        epId: item.history.epid,
        progress: item.playbackProgress,
      );
      return;
    }
    if (business == 'cheese') {
      if (item.uri?.isNotEmpty == true) {
        PageUtils.viewPgcFromUri(
          item.uri!,
          isPgc: false,
          aid: item.history.oid,
          progress: item.playbackProgress,
        );
      }
      return;
    }

    final aid = item.history.oid;
    if (aid == null) return;
    final bvid = item.history.bvid ?? IdUtils.av2bv(aid);
    int? cid = item.history.cid;
    Dimension? dimension;
    if (cid == null) {
      final res = await SearchHttp.ab2cWithDimension(
        aid: aid,
        bvid: bvid,
        part: item.history.page,
      );
      if (res != null) {
        cid = res.cid;
        dimension = res.dimension;
      }
    }
    if (cid != null) {
      PageUtils.toVideoPage(
        aid: aid,
        bvid: bvid,
        cid: cid,
        cover: item.cover,
        title: item.title,
        dimension: dimension,
        progress: item.playbackProgress,
      );
    }
  }
}

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({
    required this.date,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final DateTime date;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: enabled
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.outline.withValues(alpha: 0.1),
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: enabled
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormatUtils.longFormat.format(date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 142,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.8),
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

class _YearHistoryItem extends StatelessWidget {
  const _YearHistoryItem({required this.item, required this.onTap});

  final HistoryItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDuration = item.duration != null && item.duration != 0;
    final progress = item.progress;
    final cover = item.cover?.isNotEmpty == true
        ? item.cover
        : item.covers?.isNotEmpty == true
        ? item.covers!.first
        : '';

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          // SliverList 给条目的高度是无界的，AspectRatio 直接放在 Row 里会拿到
          // 双向无界约束并抛异常（整帧不绘制、黑屏），因此在外层取有界宽度，
          // 用 SizedBox 给封面确定尺寸，并钳制上限避免宽屏下封面过大。
          builder: (context, constraints) {
            final coverWidth = math.min(180.0, constraints.maxWidth * 0.42);
            final coverHeight = coverWidth / Style.aspectRatio;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Style.safeSpace,
                vertical: 5,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: coverWidth,
                    height: coverHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NetworkImgLayer(
                          src: cover,
                          width: coverWidth,
                          height: coverHeight,
                        ),
                        if (hasDuration)
                          PBadge(
                            text: progress == -1
                                ? '已看完'
                                : '${DurationUtils.formatDuration(progress)}/${DurationUtils.formatDuration(item.duration)}',
                            right: 6,
                            bottom: 8,
                            type: PBadgeType.gray,
                          ),
                        if (item.isFav == 1)
                          const PBadge(
                            text: '已收藏',
                            top: 6,
                            right: 6,
                            type: PBadgeType.gray,
                          ),
                        if (hasDuration && progress != null && progress != 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: VideoProgressIndicator(
                              color: theme.colorScheme.primary,
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              progress: progress == -1
                                  ? 1
                                  : progress / item.duration!,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title ?? '未命名内容',
                            maxLines: item.videos != null && item.videos! > 1
                                ? 1
                                : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: theme.textTheme.bodyMedium?.fontSize,
                              height: 1.42,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          if (item.authorName?.isNotEmpty == true)
                            Text(
                              item.authorName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          Text(
                            DateFormatUtils.chatFormat(
                              item.viewAt,
                              isHistory: true,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
