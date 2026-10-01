import 'dart:convert';

import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/fav/fav_detail/media.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 「收藏回顾」:按收藏时间年份筛选用户全部收藏的视频,并生成偏好词云。
///
/// 数据走 `/x/v3/fav/resource/list`(默认收藏夹 id + type=1 全部收藏)分页
/// 聚合,仅统计普通视频稿件(type=2);本地 favArchive 归档实现二次进入
/// 秒开,每次进入做一次全量增量刷新(分页限速)。
///
/// 统一转换为 HistoryItemModel(viewAt=收藏时间),复用年份漫游的
/// 词云、列表条目与跳转逻辑。注意:收藏条目无进度数据,时长统计按
/// 视频总时长计算。
class FavRecallController extends GetxController {
  final Rx<LoadingState<List<HistoryItemModel>>> loadingState =
      Rx<LoadingState<List<HistoryItemModel>>>(
        LoadingState<List<HistoryItemModel>>.loading(),
      );

  final RxInt selectedYear = DateTime.now().year.obs;
  final RxInt selectedMonth = 0.obs; // 0=全年,1-12=对应月份
  final RxList<int> availableYears = <int>[].obs;
  final RxString keywordFilter = ''.obs;
  final RxString progress = ''.obs;

  bool _refreshing = false;
  List<HistoryItemModel> _all = const [];

  @override
  void onInit() {
    super.onInit();
    _loadFromArchive();
    if (_all.isNotEmpty) {
      _recomputeYears();
      _apply();
    }
    refreshData();
  }

  void _loadFromArchive() {
    final list = <HistoryItemModel>[];
    for (final key in GStorage.favArchive.keys) {
      if (!(key as String).startsWith('fav_')) continue; // 跳过 folderMeta
      final raw = GStorage.favArchive.get(key);
      if (raw == null) continue;
      try {
        list.add(
          HistoryItemModel.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // 单条归档损坏不影响其余数据
      }
    }
    list.sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));
    _all = list;
  }

  Future<void> refreshData() async {
    if (_refreshing) return;
    if (!Accounts.main.isLogin) {
      loadingState.value = const Error('请先登录账号，再查看收藏回顾');
      return;
    }
    _refreshing = true;
    progress.value = '准备同步…';
    try {
      // 收藏夹列表(created/list-all,含默认夹)
      List<FavFolderInfo>? folders;
      final foldersRes = await FavHttp.allFavFolders(Accounts.main.mid);
      if (foldersRes case Success(:final response)) {
        folders = response.list;
      }
      if (folders == null || folders.isEmpty) {
        loadingState.value = const Error('未找到收藏夹');
        return;
      }
      // 归档先行,秒开
      if (_all.isNotEmpty) _apply();

      final merged = {
        for (final item in _all) 'fav_${item.history.oid}': item,
      };
      // 上次同步时各夹的 media_count 快照:数量未变的空夹跳过重扫
      final Map<String, int> lastMeta = _loadFolderMeta();
      final Map<String, int> newMeta = {};

      int collected = 0;
      // 逐夹聚合:实测 type=1(全部收藏聚合查询)对部分账号返回
      // 11010「您访问的内容不存在」,只有逐夹 type=0 可靠。
      for (final folder in folders) {
        final fid = folder.id;
        if (fid == null) continue;
        final title = folder.title ?? '收藏夹';
        final expected = folder.mediaCount ?? 0;
        newMeta['$fid'] = expected;
        if (expected == 0 && lastMeta['$fid'] == 0) continue;

        int pn = 1;
        while (true) {
          progress.value = '同步「$title」 第$pn页（已收集 $collected 条）';
          final res = await FavHttp.userFavFolderDetail(
            mediaId: fid,
            pn: pn,
            ps: 20,
            type: 0,
          );
          if (res case Success(:final response)) {
            final medias = response.medias ?? const <FavDetailItemModel>[];
            if (medias.isEmpty) break;
            for (final media in medias) {
              final converted = _convert(media);
              if (converted != null) {
                final itemKey = 'fav_${media.id}';
                if (!merged.containsKey(itemKey)) collected++;
                merged[itemKey] = converted;
                GStorage.favArchive.put(itemKey, jsonEncode(converted.toJson()));
              }
            }
            if (response.hasMore != true) break;
            pn++;
            await Future.delayed(const Duration(milliseconds: 60));
          } else {
            // 单个夹失败(如私密夹):跳过该夹继续其余
            SmartDialog.showToast('「$title」同步失败，已跳过');
            break;
          }
        }
      }
      GStorage.favArchive.put('folderMeta', jsonEncode(newMeta));
      _all = merged.values.toList()
        ..sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));
      _recomputeYears();
      _apply();
    } finally {
      _refreshing = false;
      progress.value = '';
    }
  }

  /// 上次全量同步时各收藏夹的 media_count 快照。
  Map<String, int> _loadFolderMeta() {
    final raw = GStorage.favArchive.get('folderMeta');
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return const {};
    }
  }

  /// 收藏条目 → HistoryItemModel(viewAt=收藏时间)。仅普通视频稿件;
  /// 失效视频(标题含"已失效")不参与统计与词云。
  HistoryItemModel? _convert(FavDetailItemModel media) {
    if (media.type != 2) return null;
    final favTime = media.favTime;
    if (favTime == null) return null;
    final title = media.title ?? '';
    if (title.contains('已失效')) return null;
    return HistoryItemModel(
      title: title,
      cover: media.cover,
      authorName: media.upper?.name,
      authorMid: media.upper?.mid,
      duration: media.duration,
      viewAt: favTime,
      history: History(
        business: 'fav',
        oid: media.id,
        bvid: media.bvid,
        cid: media.ugc?.firstCid,
      ),
    );
  }

  void _recomputeYears() {
    final years = <int>{DateTime.now().year};
    for (final item in _all) {
      final viewAt = item.viewAt;
      if (viewAt != null) {
        years.add(DateTime.fromMillisecondsSinceEpoch(viewAt * 1000).year);
      }
    }
    availableYears.value = years.toList()..sort((a, b) => b.compareTo(a));
  }

  /// 当前区间(年份+月份)命中的收藏记录,按收藏时间倒序。
  List<HistoryItemModel> get filtered {
    final year = selectedYear.value;
    final month = selectedMonth.value;
    return _all.where((item) {
      final viewAt = item.viewAt;
      if (viewAt == null) return false;
      final date = DateTime.fromMillisecondsSinceEpoch(viewAt * 1000);
      if (date.year != year) return false;
      if (month != 0 && date.month != month) return false;
      return true;
    }).toList();
  }

  void _apply() {
    loadingState.value = Success(filtered);
  }

  void selectYear(int year) {
    if (selectedYear.value == year) return;
    selectedYear.value = year;
    selectedMonth.value = 0;
    _apply();
  }

  void selectMonth(int month) {
    if (selectedMonth.value == month) return;
    selectedMonth.value = month;
    _apply();
  }

  void toggleKeywordFilter(String word) =>
      keywordFilter.value = keywordFilter.value == word ? '' : word;

  /// 当前区间内按关键词筛选后的记录(词云点击联动)。
  List<HistoryItemModel> get filteredByKeyword {
    final filter = keywordFilter.value;
    if (filter.isEmpty) return filtered;
    final lower = filter.toLowerCase();
    return filtered
        .where(
          (item) =>
              (item.title ?? '').toLowerCase().contains(lower) ||
              (item.authorName ?? '').toLowerCase().contains(lower),
        )
        .toList();
  }

  /// 收藏数量(当前区间)。
  int get totalCount => filtered.length;

  /// 收藏内容总时长秒数(按视频时长,收藏条目无进度数据)。
  int get totalSeconds => filtered.fold(
    0,
    (sum, item) => sum + (item.duration ?? 0),
  );

  /// 最常收藏的 UP 主(当前区间)。
  String get topUp {
    final map = <String, int>{};
    for (final item in filtered) {
      final name = item.authorName;
      if (name != null && name.isNotEmpty) {
        map[name] = (map[name] ?? 0) + 1;
      }
    }
    if (map.isEmpty) return '';
    final top = map.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return '${top.key}（${top.value} 条）';
  }

  String get totalDurationText =>
      DurationUtils.formatTimeDuration(Duration(seconds: totalSeconds));

  /// 本应用内的搜索历史(偏好词云数据源之一,与我的回顾共用)。
  List<String> get searchTerms {
    final raw = GStorage.historyWord.get('cacheList');
    return raw is List ? raw.map((e) => e.toString()).toList() : const [];
  }

  /// 本地归档总条数(展示用)。
  int get archiveCount => GStorage.favArchive.keys
      .where((key) => (key as String).startsWith('fav_'))
      .length;
}
