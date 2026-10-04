import 'package:PiliPlus/http/follow.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_avatar.dart';
import 'package:PiliPlus/models_new/follow/list.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/pages/year_roaming/ai_summary.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 「关注回顾」:按关注时间(mtime)年份分类用户关注的 UP 主。
///
/// 数据走 /x/relation/followings 全量翻页(每页20,按 total 结束,
/// 250ms 限速);关注时间为恒定值,控制器随应用生命周期缓存,
/// 仅首次进入拉取,不做本地归档。
class FollowRecallController extends GetxController {
  final Rx<LoadingState<List<FollowItemModel>>> loadingState =
      Rx<LoadingState<List<FollowItemModel>>>(
        LoadingState<List<FollowItemModel>>.loading(),
      );

  /// 年份筛选:null = 显示全部分组
  final Rx<int?> selectedYear = Rx<int?>(null);

  /// 自定义起止日期(日期按钮设置,优先于年份芯片)
  final Rx<DateTime?> customStart = Rx<DateTime?>(null);
  final Rx<DateTime?> customEnd = Rx<DateTime?>(null);
  final RxString progress = ''.obs;
  final RxString keywordFilter = ''.obs;

  bool _loaded = false;
  bool _loading = false;
  List<FollowItemModel> _all = const [];

  @override
  void onInit() {
    super.onInit();
    refreshData();
  }

  Future<void> refreshData() async {
    if (_loading) return;
    if (!Accounts.main.isLogin) {
      loadingState.value = const Error('请先登录账号，再查看关注回顾');
      return;
    }
    _loading = true;
    if (_all.isNotEmpty) {
      loadingState.value = Success(_sorted());
    }
    progress.value = '准备同步…';
    try {
      final fetched = <FollowItemModel>[];
      int pn = 1;
      int? total;
      while (true) {
        progress.value = '同步关注列表 第$pn页…';
        final res = await FollowHttp.followings(
          vmid: Accounts.main.mid,
          pn: pn,
          ps: 20,
        );
        if (res case Success(:final response)) {
          final list = response.list ?? const <FollowItemModel>[];
          fetched.addAll(list);
          total ??= response.total;
          final reached = total != null && fetched.length >= total;
          if (list.isEmpty || reached) break;
          pn++;
          await Future.delayed(const Duration(milliseconds: 250));
        } else if (res case Error(:final errMsg, :final code)) {
          if (fetched.isNotEmpty) {
            SmartDialog.showToast('部分关注列表同步失败，已展示已获取部分');
            break;
          }
          loadingState.value = Error(errMsg);
          return;
        } else {
          loadingState.value = const Error('获取关注列表失败');
          return;
        }
      }
      _all = fetched..sort((a, b) => (b.mtime ?? 0).compareTo(a.mtime ?? 0));
      _loaded = true;
      loadingState.value = Success(_sorted());
    } finally {
      _loading = false;
      progress.value = '';
    }
  }

  /// 按当前年份筛选分组( null=全部 )
  List<FollowItemModel> _sorted() {
    return _all;
  }

  List<MapEntry<int, List<FollowItemModel>>> _grouped() {
    final year = selectedYear.value;
    final cs = customStart.value;
    final ce = customEnd.value;
    Iterable<FollowItemModel> source = _all;
    if (cs != null && ce != null) {
      final start = DateTime(cs.year, cs.month, cs.day);
      final end = DateTime(ce.year, ce.month, ce.day, 23, 59, 59);
      source = _all.where((item) {
        final mtime = item.mtime;
        if (mtime == null) return false;
        final date = DateTime.fromMillisecondsSinceEpoch(mtime * 1000);
        return !date.isBefore(start) && !date.isAfter(end);
      });
    } else if (year != null) {
      source = _all.where(
        (item) =>
            item.mtime != null &&
            DateTime.fromMillisecondsSinceEpoch(item.mtime! * 1000).year ==
                year,
      );
    }
    final map = <int, List<FollowItemModel>>{};
    for (final item in source) {
      final mtime = item.mtime;
      if (mtime == null) continue;
      final y = DateTime.fromMillisecondsSinceEpoch(mtime * 1000).year;
      map.putIfAbsent(y, () => []).add(item);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return [
      for (final e in entries)
        MapEntry(
          e.key,
          e.value..sort((a, b) => (b.mtime ?? 0).compareTo(a.mtime ?? 0)),
        ),
    ];
  }

  /// 可选年份(有关注记录的年份,新→旧)
  List<int> get availableYears {
    final years = <int>{};
    for (final item in _all) {
      final mtime = item.mtime;
      if (mtime != null) {
        years.add(DateTime.fromMillisecondsSinceEpoch(mtime * 1000).year);
      }
    }
    final result = years.toList()..sort((a, b) => b.compareTo(a));
    return result;
  }

  int get totalCount => _all.length;

  /// 构建 AI 总结 prompt(统计 + 近期关注样本,不含敏感信息)。
  String buildAiPrompt() {
    final sample = _all.take(20).map((item) {
      final mtime = item.mtime;
      final date = mtime == null
          ? ''
          : '(${DateTime.fromMillisecondsSinceEpoch(mtime * 1000).year}年关注)';
      final sign = item.sign?.isNotEmpty == true ? ':${item.sign}' : '';
      return '${item.uname ?? ''}$date$sign';
    }).join(';');
    final perYear = <int, int>{};
    for (final item in _all) {
      final mtime = item.mtime;
      if (mtime == null) continue;
      final y = DateTime.fromMillisecondsSinceEpoch(mtime * 1000).year;
      perYear[y] = (perYear[y] ?? 0) + 1;
    }
    final perYearText =
        perYear.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    final perYearStr = perYearText
        .take(8)
        .map((e) => '${e.key}年${e.value}人')
        .join('、');
    final yearNote = selectedYear.value != null
        ? '- 当前筛选的 ${selectedYear.value} 年新增 $currentYearCount 人\n'
        : '';
    return '我的B站关注列表数据如下(共 ${_all.length} 人):\n'
        '- 按关注年份:$perYearStr\n'
        '$yearNote- 近期关注的样本:$sample\n'
        '请总结我关注博主的风格和兴趣偏好(按时期归纳)。';
  }

  /// 当前筛选年份的新增关注数(year==null 时返回总数)。
  int get currentYearCount {
    final year = selectedYear.value;
    if (year == null) return _all.length;
    return _grouped().fold(0, (sum, e) => sum + e.value.length);
  }

  /// 最早关注时间(无数据返回 null)。
  DateTime? get earliestFollow {
    DateTime? earliest;
    for (final item in _all) {
      final mtime = item.mtime;
      if (mtime == null) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(mtime * 1000);
      if (earliest == null || date.isBefore(earliest)) earliest = date;
    }
    return earliest;
  }

  /// 日期按钮:设置自定义起止(两个都设后生效,按 mtime 范围过滤)。
  Future<void> pickCustomDate({required bool isStart}) async {
    final anchor = isStart ? buttonStartDate : buttonEndDate;
    final picked = await showDatePicker(
      context: Get.context!,
      initialDate: anchor,
      firstDate: earliestFollow ?? DateTime(2009, 6, 26),
      lastDate: DateTime.now(),
      helpText: isStart ? '选择开始日期' : '选择结束日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    if (isStart) {
      customStart.value = picked;
      if (customEnd.value != null && customEnd.value!.isBefore(picked)) {
        customEnd.value = picked;
      }
    } else {
      customEnd.value = picked;
      if (customStart.value != null && customStart.value!.isAfter(picked)) {
        customStart.value = picked;
      }
    }
    if (customStart.value != null && customEnd.value != null) {
      selectedYear.value = null;
      loadingState.value = Success(_sorted());
    }
  }

  DateTime get buttonStartDate {
    if (customStart.value != null) return customStart.value!;
    return earliestFollow ?? DateTime.now();
  }

  DateTime get buttonEndDate {
    if (customEnd.value != null) return customEnd.value!;
    return DateTime.now();
  }

  void selectYear(int? year) {
    if (selectedYear.value == year) return;
    selectedYear.value = year;
    _clearCustom();
    loadingState.value = Success(_sorted());
  }

  void _clearCustom() {
    customStart.value = null;
    customEnd.value = null;
  }

  void toggleKeywordFilter(String word) =>
      keywordFilter.value = keywordFilter.value == word ? '' : word;
}

/// 「关注回顾」区段:年份芯片 + 迷你统计 + 按关注年份分组的 UP 列表。
class FollowRecallView {
  FollowRecallView({required this.controller, required this.onToggleFilter});

  final FollowRecallController controller;
  final void Function(String word) onToggleFilter;

  /// 返回区段 slivers(嵌入年份漫游页 CustomScrollView)。
  List<Widget> buildSlivers(BuildContext context) {
    final theme = Theme.of(context);
    return switch (controller.loadingState.value) {
      Loading() => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Center(child: CircularProgressIndicator()),
                if (controller.progress.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      controller.progress.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      Error(:final errMsg) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Text(
                  errMsg ?? '获取关注列表失败',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: controller.refreshData,
                  child: const Text('点击重试'),
                ),
              ],
            ),
          ),
        ),
      ],
      Success(:final response) => _buildContent(theme, controller._grouped()),
    };
  }

  List<Widget> _buildContent(
    ThemeData theme,
    List<MapEntry<int, List<FollowItemModel>>> groups,
  ) {
    final colorScheme = theme.colorScheme;
    final earliest = controller.earliestFollow;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '选择关注年份',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  AiSummaryButton(
                    title: '关注回顾',
                    promptBuilder: controller.buildAiPrompt,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${controller.currentYearCount} 人',
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 8,
                  children: [
                    SearchText(
                      text: '全部年份',
                      onTap: (_) => controller.selectYear(null),
                      bgColor: controller.selectedYear.value == null
                          ? colorScheme.secondaryContainer
                          : null,
                      textColor: controller.selectedYear.value == null
                          ? colorScheme.onSecondaryContainer
                          : null,
                    ),
                    for (final y in controller.availableYears)
                      SearchText(
                        text: '$y',
                        onTap: (_) => controller.selectYear(y),
                        bgColor: controller.selectedYear.value == y
                            ? colorScheme.secondaryContainer
                            : null,
                        textColor: controller.selectedYear.value == y
                            ? colorScheme.onSecondaryContainer
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
                    child: _DateButton(
                      date: controller.buttonStartDate,
                      label: '开始日期',
                      onTap: () => controller.pickCustomDate(isStart: true),
                    ),
                  ),
                  Text('至', style: TextStyle(color: colorScheme.outline)),
                  Expanded(
                    child: _DateButton(
                      date: controller.buttonEndDate,
                      label: '结束日期',
                      onTap: () => controller.pickCustomDate(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '数据来源：B站关注列表（按关注时间分组）。'
                '${earliest != null ? '你的最早关注记录是 ${earliest.year} 年。' : ''}'
                '共关注 ${controller.totalCount} 人。',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        sliver: SliverMainAxisGroup(
          slivers: [
            for (final group in groups) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '${group.key} 年',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '新增关注 ${group.value.length} 人',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemBuilder: (context, index) =>
                    _FollowTile(item: group.value[index], theme: theme),
                itemCount: group.value.length,
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

/// 单个关注 UP 行:头像(含认证角标)+ 昵称 + 签名 + 关注日期。
class _FollowTile extends StatelessWidget {
  const _FollowTile({required this.item, required this.theme});

  final FollowItemModel item;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    final mtime = item.mtime;
    final dateText = mtime == null ? '' : DateFormatUtils.dateFormat(mtime);
    final official = item.officialVerify;
    final verifyDesc = official != null && official.type != -1
        ? (official.desc?.isNotEmpty == true ? official.desc! : '认证')
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: item.face != null && item.face!.isNotEmpty
                    ? NetworkImage(item.face!)
                    : null,
                child: item.face == null || item.face!.isEmpty
                    ? const Icon(Icons.person_outline, size: 20)
                    : null,
              ),
              if (verifyDesc != null)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Icon(
                    official!.type == 1
                        ? Icons.verified
                        : Icons.verified_outlined,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.uname ?? '未知用户',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (item.attribute == 2) ...[
                      const SizedBox(width: 6),
                      Text(
                        '特别关注',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.sign?.isNotEmpty == true)
                  Text(
                    item.sign!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            dateText,
            style: TextStyle(fontSize: 11, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

/// 关注回顾的日期按钮(简洁版,点击弹出单日日历)。
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.date,
    required this.label,
    required this.onTap,
  });

  final DateTime date;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 13,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${DateFormatUtils.longFormat.format(date)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
