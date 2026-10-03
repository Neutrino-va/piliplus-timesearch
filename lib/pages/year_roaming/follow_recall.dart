import 'package:PiliPlus/http/follow.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_avatar.dart';
import 'package:PiliPlus/models_new/follow/list.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
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
    final source = year == null
        ? _all
        : _all
              .where(
                (item) =>
                    item.mtime != null &&
                    DateTime.fromMillisecondsSinceEpoch(
                          item.mtime! * 1000,
                        ).year ==
                        year,
              )
              .toList();
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

  void selectYear(int? year) {
    if (selectedYear.value == year) return;
    selectedYear.value = year;
    loadingState.value = Success(_sorted());
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
