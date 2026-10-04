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
import 'package:PiliPlus/pages/year_recall/feed_controller.dart';
import 'package:PiliPlus/pages/year_recall/view.dart';
import 'package:PiliPlus/pages/year_roaming/controller.dart';
import 'package:PiliPlus/pages/year_roaming/fav_recall.dart';
import 'package:PiliPlus/pages/year_roaming/ai_summary.dart';
import 'package:PiliPlus/pages/year_roaming/follow_recall.dart';
import 'package:PiliPlus/pages/year_roaming/heatmap_card.dart';
import 'package:PiliPlus/pages/year_roaming/my_likes_rank.dart';
import 'package:PiliPlus/pages/year_roaming/word_cloud.dart';
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

  /// 「考古推荐流」控制器（每周必看聚合），仅在推荐流模式下懒创建。
  YearRecallFeedController? _feedController;

  /// 「收藏回顾」控制器懒创建。
  FavRecallController? _favController;

  /// 「关注回顾」控制器懒创建。
  FollowRecallController? _followController;

  /// 功能目录定位用 GlobalKey(概览/热力/分区/词云/获赞/列表)。
  final GlobalKey _summaryKey = GlobalKey();
  final GlobalKey _heatmapKey = GlobalKey();
  final GlobalKey _zoneKey = GlobalKey();
  final GlobalKey _cloudKey = GlobalKey();
  final GlobalKey _likesKey = GlobalKey();
  final GlobalKey _listHeaderKey = GlobalKey();

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  /// 词云点击筛选后,自动滚到观看列表顶部。
  void _scrollToListHeader() {
    final ctx = _listHeaderKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  YearRecallController? get _recall {
    if (_controller.pageMode.value != 1) return null;
    // putOrFind 与其他入口共享实例，避免重复创建。
    final controller = _recallController ??=
        Get.putOrFind<YearRecallController>(
          YearRecallController.new,
        );
    return controller;
  }

  YearRecallFeedController? get _feed {
    final keywordController = _recall;
    if (keywordController == null || !keywordController.feedMode.value) {
      return null;
    }
    final feedController = _feedController ??=
        Get.putOrFind<YearRecallFeedController>(
          YearRecallFeedController.new,
        );
    feedController.ensureSeriesList();
    return feedController;
  }

  FavRecallController? get _fav {
    if (_controller.pageMode.value != 2) return null;
    final controller = _favController ??= Get.putOrFind<FavRecallController>(
      FavRecallController.new,
    );
    return controller;
  }

  FollowRecallController? get _follow {
    if (_controller.pageMode.value != 3) return null;
    final controller = _followController ??=
        Get.putOrFind<FollowRecallController>(
          FollowRecallController.new,
        );
    return controller;
  }

  void _setPageMode(int mode) {
    if (_controller.pageMode.value == mode) return;
    _controller.pageMode.value = mode;
    if (mode == 1) {
      _recallController ??= Get.putOrFind<YearRecallController>(
        YearRecallController.new,
      );
    }
    if (mode == 2) {
      _favController ??= Get.putOrFind<FavRecallController>(
        FavRecallController.new,
      );
    }
    if (mode == 3) {
      _followController ??= Get.putOrFind<FollowRecallController>(
        FollowRecallController.new,
      );
    }
    _scrollController.jumpTo(0);
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
              if (_controller.pageMode.value == 3)
                ...switch (_follow) {
                  final followController? => FollowRecallView(
                    controller: followController,
                    onToggleFilter: (word) {
                      followController.toggleKeywordFilter(word);
                      _scrollToListHeader();
                    },
                  ).buildSlivers(context),
                  null => [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ],
                }
              else if (_controller.pageMode.value == 2)
                ...switch (_fav) {
                  final favController? => _buildFavSection(
                    theme,
                    favController,
                  ),
                  null => [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ],
                }
              else if (_recall case final recallController?) ...[
                ...YearRecallView.buildSlivers(theme, recallController, _feed),
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

  /// 顶部模式切换：「我的回顾」/「年份回顾」/「收藏回顾」。
  Widget _buildModeSwitch(ThemeData theme) {
    final mode = _controller.pageMode.value;
    Widget chip(String text, int value) => SearchText(
      text: text,
      bgColor: mode == value ? theme.colorScheme.secondaryContainer : null,
      textColor: mode == value ? theme.colorScheme.onSecondaryContainer : null,
      onTap: (_) => _setPageMode(value),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        spacing: 8,
        children: [
          chip('我的回顾', 0),
          chip('年份回顾', 1),
          chip('收藏回顾', 2),
          chip('关注回顾', 3),
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
              children: [
                for (final month in _controller.availableMonths)
                  SearchText(
                    text: month == 0 ? '全年' : '$month月',
                    onTap: (_) => _controller.selectMonth(month),
                    bgColor: _controller.selectedMonth.value == month
                        ? theme.colorScheme.secondaryContainer
                        : null,
                    textColor: _controller.selectedMonth.value == month
                        ? theme.colorScheme.onSecondaryContainer
                        : null,
                  ),
              ],
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
                  enabled: true,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              Text('至', style: TextStyle(color: theme.colorScheme.outline)),
              Expanded(
                child: _DateRangeButton(
                  date: rangeEnd,
                  label: '结束日期',
                  enabled: true,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '数据来源：B站观看历史（仅保留约一年）+ 本地归档（共 '
            '${_controller.archiveCount} 条，会随使用持续积累）。'
            '统计口径：按该范围内的观看记录计算；“最喜欢”指范围内看过且当前仍在收藏夹中的内容；'
            '“观看时长”按观看进度估算。',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// 单日日历弹窗(开始/结束分开选择,可翻月/切换年份)。
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

  /// 「收藏回顾」区段:年份/月份芯片 + 迷你统计 + 偏好词云 + 收藏列表。
  List<Widget> _buildFavSection(
    ThemeData theme,
    FavRecallController fav,
  ) {
    return switch (fav.loadingState.value) {
      Loading() => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 60),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正在同步收藏数据…',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fav.progressValue.value,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.06,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      fav.totalPages.value > 0
                          ? '${fav.pagesDone.value}/${fav.totalPages.value} 页'
                          : '正在获取收藏夹…',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(fav.progressValue.value * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (fav.progress.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      fav.progress.value,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '首次全量同步约需一分钟（每页限速以防风控），'
                  '之后仅在收藏变化时增量拉取。',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      Error(:final errMsg) => [
        HttpError(errMsg: errMsg, onReload: fav.refreshData),
      ],
      Success(:final response) => [
        SliverToBoxAdapter(child: _buildFavHeader(theme, fav)),
        SliverToBoxAdapter(child: _buildFavStats(theme, fav)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: WordCloudCard(
              colorScheme: theme.colorScheme,
              records: response,
              searchTerms: fav.searchTerms,
              currentFilter: fav.keywordFilter.value,
              onToggle: fav.toggleKeywordFilter,
            ),
          ),
        ),
        if (fav.keywordFilter.value.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                spacing: 8,
                children: [
                  Text(
                    '已按「${fav.keywordFilter.value}」筛选，'
                    '共 ${fav.filteredByKeyword.length} 条',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  SearchText(
                    text: '清除筛选',
                    onTap: (_) => fav.toggleKeywordFilter(
                      fav.keywordFilter.value,
                    ),
                  ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 8),
          sliver: SliverList.builder(
            itemBuilder: (context, index) => _YearHistoryItem(
              item: fav.filteredByKeyword[index],
              onTap: () => _openHistoryItem(fav.filteredByKeyword[index]),
            ),
            itemCount: fav.filteredByKeyword.length,
          ),
        ),
      ],
    };
  }

  /// 收藏回顾的年份/月份选择与数据来源说明。
  Widget _buildFavHeader(ThemeData theme, FavRecallController fav) {
    final year = fav.selectedYear.value;
    final lastMonth = year == DateTime.now().year ? DateTime.now().month : 12;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '选择收藏年份',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '$year 年收藏',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (final y in fav.availableYears)
                  SearchText(
                    text: '$y',
                    onTap: (_) => fav.selectYear(y),
                    bgColor: year == y
                        ? theme.colorScheme.secondaryContainer
                        : null,
                    textColor: year == y
                        ? theme.colorScheme.onSecondaryContainer
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (final m in [0, ...List.generate(lastMonth, (i) => i + 1)])
                  SearchText(
                    text: m == 0 ? '全年' : '$m月',
                    onTap: (_) => fav.selectMonth(m),
                    bgColor: fav.selectedMonth.value == m
                        ? theme.colorScheme.secondaryContainer
                        : null,
                    textColor: fav.selectedMonth.value == m
                        ? theme.colorScheme.onSecondaryContainer
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: _DateRangeButton(
                  date: fav.buttonStartDate,
                  label: '开始日期',
                  enabled: true,
                  onTap: () => fav.pickCustomDate(isStart: true),
                ),
              ),
              Text('至', style: TextStyle(color: theme.colorScheme.outline)),
              Expanded(
                child: _DateRangeButton(
                  date: fav.buttonEndDate,
                  label: '结束日期',
                  enabled: true,
                  onTap: () => fav.pickCustomDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '数据来源：B站收藏夹（全部收藏，仅统计普通视频）+ 本地归档'
            '（共 ${fav.archiveCount} 条）。按收藏时间计算，与视频投稿年份无关；'
            '词云反映该时段收藏内容的偏好。',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  /// 收藏回顾迷你统计卡。
  Widget _buildFavStats(ThemeData theme, FavRecallController fav) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: Style.mdRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${fav.selectedYear.value} · 我的收藏回顾',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AiSummaryButton(
                  title: '收藏回顾',
                  promptBuilder: () {
                    final titles = fav.filtered
                        .take(30)
                        .map((item) => item.title ?? '')
                        .where((t) => t.isNotEmpty)
                        .join(';');
                    return '我的B站收藏回顾数据如下(按收藏时间,'
                        '${fav.selectedYear.value}年'
                        '${fav.selectedMonth.value == 0 ? '全年' : '${fav.selectedMonth.value}月'}):\n'
                        '- 共收藏 ${fav.totalCount} 条,内容总时长 ${fav.totalDurationText}\n'
                        '- 最常收藏 UP:${fav.topUp.isEmpty ? '无' : fav.topUp}\n'
                        '- 收藏标题样本:$titles\n'
                        '请总结我这一时段的收藏风格和内容偏好。';
                  },
                ),
              ],
            ),
            Text(
              '${fav.selectedMonth.value == 0 ? '全年' : '${fav.selectedMonth.value}月'}'
              '共收藏 ${fav.totalCount} 条 · 内容总时长 ${fav.totalDurationText}',
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
            if (fav.topUp.isNotEmpty)
              Text(
                '最常收藏 UP：${fav.topUp}',
                style: TextStyle(color: theme.colorScheme.onSurface),
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
    final filter = _controller.keywordFilter.value;
    final visible = filter.isEmpty
        ? records
        : records
              .where(
                (item) =>
                    (item.title ?? '').toLowerCase().contains(
                      filter.toLowerCase(),
                    ) ||
                    (item.tagName ?? '').toLowerCase().contains(
                      filter.toLowerCase(),
                    ) ||
                    (item.authorName ?? '').toLowerCase().contains(
                      filter.toLowerCase(),
                    ),
              )
              .toList();
    return [
      SliverToBoxAdapter(child: _buildSummary(theme, records, highlight)),
      if (filter.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              spacing: 8,
              children: [
                Text(
                  '已按「$filter」筛选，共 ${visible.length} 条',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                  ),
                ),
                SearchText(
                  text: '清除筛选',
                  onTap: (_) => _controller.toggleKeywordFilter(filter),
                ),
              ],
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        sliver: SliverList.builder(
          itemBuilder: (context, index) => _YearHistoryItem(
            item: visible[index],
            onTap: () => _openHistoryItem(visible[index]),
          ),
          itemCount: visible.length,
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
          KeyedSubtree(
            key: _summaryKey,
            child: _buildDirectoryCard(theme, records.length),
          ),
          const SizedBox(height: 10),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${_controller.selectedYear.value} · 我的年度回顾',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    AiSummaryButton(
                      title: '我的回顾',
                      promptBuilder: () => _buildAiPrompt(records),
                    ),
                  ],
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
          KeyedSubtree(
            key: _heatmapKey,
            child: HeatmapCard(
              colorScheme: theme.colorScheme,
              watchCounts: _watchHeatmapData(records),
              favCounts: _favHeatmapData(),
              year: _controller.rangeStart.value.year,
            ),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _zoneKey,
            child: _buildZoneStats(theme, records.length),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _cloudKey,
            child: WordCloudCard(
              colorScheme: theme.colorScheme,
              records: records,
              searchTerms: _controller.searchTerms,
              currentFilter: _controller.keywordFilter.value,
              onToggle: (word) {
                _controller.toggleKeywordFilter(word);
                _scrollToListHeader();
              },
            ),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _likesKey,
            child: MyLikesRankCard(colorScheme: theme.colorScheme),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _listHeaderKey,
            child: Text(
              '这一年的观看内容',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分区统计（小黑盒游戏时长统计风格）：
  /// 每个分区一行——名称、按观看时长占比绘制的横条、总时长与条数，
  /// 以及该分区观看时长最长的视频。统计范围跟随当前选择的区间（全年/单月）。
  /// 构建我的回顾 AI 总结 prompt(统计摘要 + 高频词,不含完整历史)。
  String _buildAiPrompt(List<HistoryItemModel> records) {
    final zones = _controller.zoneStats
        .take(3)
        .map((s) => '${s.name} ${s.count} 条')
        .join('、');
    final ups = <String, int>{};
    for (final item in records) {
      final name = item.authorName;
      if (name != null && name.isNotEmpty) {
        ups[name] = (ups[name] ?? 0) + 1;
      }
    }
    final topUps = ups.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    final upText = topUps
        .take(3)
        .map((e) => '${e.key} ${e.value} 条')
        .join('、');
    final words = mineWords(records, const [])
        .take(15)
        .map((w) => w.text)
        .join('、');
    return '我的一段${_controller.rangeDescription}的B站观看回顾数据如下:\n'
        '- 观看 ${records.length} 条,总时长约 ${_controller.formatWatchDuration()},'
        '看完 ${_controller.completedCount.value} 条,仍在收藏 ${_controller.favoriteCount.value} 条\n'
        '- 常看分区:$zones\n'
        '- 常看UP主:$upText\n'
        '- 标题高频词:$words\n'
        '请总结我这段时期的观看风格和兴趣偏好。';
  }

  /// 热力图·观看数据:当年每日观看次数(viewAt 秒级 → yyyyMMdd)。
  Map<int, int> _watchHeatmapData(List<HistoryItemModel> records) {
    final year = _controller.rangeStart.value.year;
    final map = <int, int>{};
    for (final item in records) {
      final viewAt = item.viewAt;
      if (viewAt == null) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(viewAt * 1000);
      if (date.year != year) continue;
      final key = date.year * 10000 + date.month * 100 + date.day;
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  /// 热力图·收藏数据:当年每日收藏次数(来自收藏归档)。
  Map<int, int> _favHeatmapData() {
    final year = _controller.rangeStart.value.year;
    final map = <int, int>{};
    for (final item in FavRecallController.loadFavArchiveItems()) {
      final viewAt = item.viewAt;
      if (viewAt == null) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(viewAt * 1000);
      if (date.year != year) continue;
      final key = date.year * 10000 + date.month * 100 + date.day;
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  /// 功能目录卡(二级菜单):点击滚动定位到对应板块。
  Widget _buildDirectoryCard(ThemeData theme, int recordCount) {
    final colorScheme = theme.colorScheme;
    final entries = [
      (Icons.emoji_events_outlined, '概览总结', _summaryKey),
      (Icons.local_fire_department_outlined, '活跃热力图', _heatmapKey),
      (Icons.donut_large_outlined, '分区统计', _zoneKey),
      (Icons.cloud_outlined, '偏好词云', _cloudKey),
      (Icons.thumb_up_alt_outlined, '获赞排行', _likesKey),
      (Icons.video_library_outlined, '观看列表', _listHeaderKey),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: Style.mdRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              Text(
                '功能目录',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '点击直达 · 基于 $recordCount 条记录',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                GestureDetector(
                  onTap: () => _scrollToSection(entry.$3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Icon(entry.$1, size: 15, color: colorScheme.primary),
                        Text(
                          entry.$2,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildZoneStats(ThemeData theme, int recordCount) {
    final stats = _controller.zoneStats;
    if (stats.isEmpty) return const SizedBox.shrink();
    final maxSeconds = stats.first.seconds;
    final showCount = stats.length > 12 ? 12 : stats.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: Style.mdRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Row(
            children: [
              Text(
                '分区统计',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '基于已加载的 $recordCount 条记录',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          for (final stat in stats.take(showCount))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Row(
                  children: [
                    Text(
                      stat.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DurationUtils.formatTimeDuration(
                        Duration(seconds: stat.seconds),
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${stat.count}条',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: math.max(
                        4.0,
                        constraints.maxWidth *
                            (maxSeconds == 0 ? 0.0 : stat.seconds / maxSeconds),
                      ),
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.75,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '⏱ 最久观看',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        stat.topTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      DurationUtils.formatDuration(stat.topSeconds),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          if (stats.length > showCount)
            Text(
              '还有 ${stats.length - showCount} 个分区未展示',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
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
    this.subLabel,
  });

  final DateTime date;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  /// 可选副标题(当前区间摘要),显示在日期行下方。
  final String? subLabel;

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
              if (subLabel != null)
                Text(
                  subLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: enabled
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurface,
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
