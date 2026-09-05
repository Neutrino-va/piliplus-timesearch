import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models_new/history/data.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

class YearRoamingController
    extends CommonListController<List<HistoryItemModel>, HistoryItemModel> {
  YearRoamingController({int? initialYear})
    : selectedYear = (initialYear ?? DateTime.now().year).obs,
      rangeStart = _yearStart(initialYear ?? DateTime.now().year).obs,
      rangeEnd = _yearEnd(initialYear ?? DateTime.now().year).obs;

  static final DateTime firstAvailableDate = DateTime(2009, 6, 26);

  final RxInt selectedYear;
  final Rx<DateTime> rangeStart;
  final Rx<DateTime> rangeEnd;

  /// 页面模式：false=「我的回顾」（按观看时间），true=「年份回顾」（按发布年份浏览）。
  final RxBool recallMode = false.obs;

  /// 已从服务端见过的最早一条记录。仅在游标自然走到尽头（dataEndReached）
  /// 时才是可信的数据边界；被 60 页上限截断的查询不能作为依据。
  final Rx<DateTime?> dataOldest = Rx<DateTime?>(null);

  /// 是否有任一次查询自然遍历到数据尽头（服务端不再返回更多）。
  bool dataEndReached = false;

  /// 已确认存在观看记录的年份（来自实际取到的记录），作为年份芯片的依据。
  final RxList<int> yearsWithData = <int>[].obs;

  /// 已锚定探测、确认没有数据的年份，不再展示为可选项。
  final RxList<int> emptyYears = <int>[].obs;

  final RxInt watchedCount = 0.obs;
  final RxInt completedCount = 0.obs;
  final RxInt totalWatchedSeconds = 0.obs;
  final RxInt favoriteCount = 0.obs;
  final RxString favoriteTitle = ''.obs;
  final RxString favoriteAuthor = ''.obs;
  final RxString mostWatchedAuthor = ''.obs;
  final RxInt mostWatchedAuthorCount = 0.obs;
  final RxString mostWatchedTag = ''.obs;
  final RxInt mostWatchedTagCount = 0.obs;

  Account get account => Accounts.history;

  /// 调试专用文件日志：写入应用私有目录，便于真机排查游标问题。
  /// 仅 Debug 构建生效；日志只包含游标与条数，不含任何 Cookie/Token。
  static Future<void> _logLine(String message) async {
    if (!kDebugMode) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/year_roaming_debug.log');
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 日志失败不影响业务
    }
  }

  /// 供视图层使用的调试日志入口
  static Future<void> debugLog(String message) => _logLine(message);

  int get currentYear => DateTime.now().year;

  DateTime get latestDate => DateTime.now();

  List<int> get availableYears {
    // 只展示确认有数据的年份：当前年份 + 实际取到过记录的年份，
    // 剔除已锚定探测为空的年份；若某次查询自然走到数据尽头，
    // 则用真实边界补齐中间年份（期间必有数据，最迟可由锚定探测确认）。
    final Set<int> years = {currentYear, ...yearsWithData};
    if (dataEndReached && dataOldest.value != null) {
      for (
        int year = dataOldest.value!.year;
        year <= currentYear;
        year++
      ) {
        years.add(year);
      }
    }
    final result = years.where((year) => !emptyYears.contains(year)).toList()
      ..sort((a, b) => b.compareTo(a));
    return result.isEmpty ? [currentYear] : result;
  }

  /// 日期选择器的最早可选日期：边界未探明前保持 2009 年可探，
  /// 已探明后收窄到真实数据起点。
  DateTime get pickerFirstDate =>
      (dataEndReached && dataOldest.value != null)
      ? dataOldest.value!
      : firstAvailableDate;

  HistoryItemModel? get highlightItem {
    final records = loadingState.value.dataOrNull;
    return records == null ? null : _findHighlight(records);
  }

  String get rangeDescription =>
      '${DateFormatUtils.longFormat.format(rangeStart.value)} 至 '
      '${DateFormatUtils.longFormat.format(rangeEnd.value)}';

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<void> onRefresh() {
    resetStatistics();
    return super.onRefresh();
  }

  @override
  Future<LoadingState<List<HistoryItemModel>>> customGetData() async {
    if (!account.isLogin) {
      return const Error('请先登录账号，再查看年度漫游');
    }

    final startTimestamp = _toTimestamp(rangeStart.value);
    final endTimestamp = _toTimestamp(rangeEnd.value);
    // 每次刷新重写日志，避免文件无限增长
    if (kDebugMode) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final logFile = File('${dir.path}/year_roaming_debug.log');
        if (logFile.existsSync()) logFile.delete();
      } catch (_) {}
    }
    final records = <HistoryItemModel>[];
    final recordKeys = <String>{};
    int? max;
    String? business;
    String? lastCursor;

    // 锚定分页：查询今天之前就结束的区间时，首请求直接把 view_at 锚定在
    // 区间末端，避免把请求额度浪费在区间之后（更晚）的数据上；
    // 包含今天的区间（如当前年份）仍从最新开始。
    final DateTime now = DateTime.now();
    final bool anchoredPast = rangeEnd.value.isBefore(
      DateTime(now.year, now.month, now.day),
    );
    final int? firstViewAt = anchoredPast ? endTimestamp : null;
    int? viewAt = firstViewAt;

    // 严格使用服务端返回的 cursor 作为下一页指针；
    // max/view_at/business 必须整体来自 cursor，禁止用列表末项伪造游标。
    for (int request = 0; request < 60; request++) {
      await _logLine(
        '第${request + 1}次请求: max=$max view_at=$viewAt business=$business'
        '${request == 0 && anchoredPast ? " (锚定于区间末端)" : ""}',
      );
      final LoadingState<HistoryData> res;
      try {
        res = await UserHttp.historyList(
          type: 'all',
          max: max,
          viewAt: viewAt,
          business: business,
          account: account,
        );
      } catch (e) {
        _logLine('请求异常: $e');
        return Error('获取观看历史失败：$e');
      }

      if (res case Success(:final response)) {
        final list = response.list ?? const <HistoryItemModel>[];
        await _logLine(
          '本页${list.length}条, cursor.max=${response.cursor?.max}, '
          'cursor.view_at=${response.cursor?.viewAt}, '
          'cursor.business=${response.cursor?.business}, '
          '累计命中${records.length}条',
        );
        if (list.isEmpty) {
          // 服务端不再返回数据：本次走到的位置即真实数据边界。
          dataEndReached = true;
          // 锚定探测的历史区间首页就为空：该年份确认无记录。
          // 仅在首页为空时标记，避免翻页中断导致的误判。
          if (anchoredPast && records.isEmpty && request == 0) {
            _markEmptyYear();
          }
          break;
        }

        // 记录服务端数据的时间下限与有数据年份（跨查询累积）。
        for (final item in list) {
          final itemViewAt = item.viewAt;
          if (itemViewAt == null) continue;
          final itemDate = DateTime.fromMillisecondsSinceEpoch(
            itemViewAt * 1000,
          );
          final current = dataOldest.value;
          if (current == null || itemDate.isBefore(current)) {
            dataOldest.value = itemDate;
          }
          if (!yearsWithData.contains(itemDate.year)) {
            yearsWithData.add(itemDate.year);
          }
        }

        for (final item in list) {
          final itemViewAt = item.viewAt;
          if (itemViewAt == null ||
              itemViewAt < startTimestamp ||
              itemViewAt > endTimestamp) {
            continue;
          }
          final key = _recordKey(item);
          if (recordKeys.add(key)) {
            records.add(item);
          }
        }

        final oldest = list.last.viewAt;
        final cursorData = response.cursor;
        final nextMax = cursorData?.max;
        final nextViewAt = cursorData?.viewAt;
        // 服务端未返回完整游标（max 或 view_at 缺失）时停止翻页，
        // 不再用 list.last.history.oid 等列表数据拼造无效游标。
        if (nextMax == null || nextViewAt == null) {
          dataEndReached = true;
          break;
        }
        final nextBusiness = cursorData?.business;

        final cursor = '$nextMax:$nextViewAt:$nextBusiness';
        if (cursor == lastCursor) {
          dataEndReached = true;
          break;
        }
        lastCursor = cursor;
        max = nextMax;
        viewAt = nextViewAt;
        business = nextBusiness;

        if (oldest != null && oldest < startTimestamp) {
          break;
        }
      } else if (res case Error(:final errMsg, :final code)) {
        _logLine('接口返回错误: code=$code message=$errMsg');
        return Error(errMsg, code: code);
      } else {
        _logLine('接口返回未知状态: $res');
        return const Error(null);
      }
    }

    await _logLine('加载完成, 共${records.length}条记录');
    records.sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));
    return Success(records);
  }

  /// 当前选择的年份区间确认无数据时登记，供年份选项动态剔除。
  void _markEmptyYear() {
    final year = rangeStart.value.year;
    if (rangeStart.value == _yearStart(year) &&
        !emptyYears.contains(year) &&
        year != currentYear) {
      emptyYears.add(year);
      _logLine('标记年份 $year 无历史数据');
    }
  }

  @override
  List<HistoryItemModel>? getDataList(List<HistoryItemModel> response) =>
      response;

  @override
  bool customHandleResponse(
    bool isRefresh,
    Success<List<HistoryItemModel>> response,
  ) {
    if (isRefresh) {
      updateStatistics(response.response);
    }
    // customGetData 已经把选中范围的记录一次性取完。
    isEnd = true;
    return false;
  }

  @override
  Future<void> onLoadMore() async {}

  void selectYear(int year) {
    final now = latestDate;
    final start = _yearStart(year);
    final end = _yearEnd(year).isAfter(now) ? now : _yearEnd(year);
    selectRange(start, end);
  }

  void selectRange(DateTime start, DateTime end) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(
      end.year,
      end.month,
      end.day,
      23,
      59,
      59,
    );
    final safeStart = normalizedStart.isBefore(firstAvailableDate)
        ? firstAvailableDate
        : normalizedStart;
    final safeEnd = normalizedEnd.isAfter(latestDate)
        ? latestDate
        : normalizedEnd;

    if (safeEnd.isBefore(safeStart)) return;
    if (rangeStart.value == safeStart && rangeEnd.value == safeEnd) return;

    rangeStart.value = safeStart;
    rangeEnd.value = safeEnd;
    selectedYear.value = safeStart.year;
    resetStatistics();
    onReload();
  }

  bool isYearSelected(int year) {
    final expectedStart = _yearStart(year);
    final expectedEnd = _yearEnd(year);
    return rangeStart.value == expectedStart && rangeEnd.value == expectedEnd;
  }

  /// 当前区间是否偏离所选年份的默认范围（用于日期按钮的选中态样式）。
  bool get isCustomRange {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    return !sameDay(rangeStart.value, _yearStart(selectedYear.value)) ||
        !sameDay(rangeEnd.value, _yearEnd(selectedYear.value));
  }

  static DateTime _yearStart(int year) => year == firstAvailableDate.year
      ? firstAvailableDate
      : DateTime(year, 1, 1);

  static DateTime _yearEnd(int year) {
    final now = DateTime.now();
    final end = DateTime(year, 12, 31, 23, 59, 59);
    return end.isAfter(now) ? now : end;
  }

  int _toTimestamp(DateTime date) => date.millisecondsSinceEpoch ~/ 1000;

  String _recordKey(HistoryItemModel item) {
    final history = item.history;
    return '${history.business}:${history.oid}:${history.epid}:'
        '${history.cid}:${item.viewAt}';
  }

  int _watchedSeconds(HistoryItemModel item) {
    if (item.progress == -1) return item.duration ?? 0;
    final progress = item.progress;
    return progress != null && progress > 0 ? progress : 0;
  }

  void resetStatistics() {
    watchedCount.value = 0;
    completedCount.value = 0;
    totalWatchedSeconds.value = 0;
    favoriteCount.value = 0;
    favoriteTitle.value = '';
    favoriteAuthor.value = '';
    mostWatchedAuthor.value = '';
    mostWatchedAuthorCount.value = 0;
    mostWatchedTag.value = '';
    mostWatchedTagCount.value = 0;
  }

  void updateStatistics(List<HistoryItemModel> records) {
    watchedCount.value = records.length;
    completedCount.value = records.where((item) => item.progress == -1).length;
    totalWatchedSeconds.value = records.fold<int>(
      0,
      (total, item) => total + _watchedSeconds(item),
    );
    favoriteCount.value = records.where((item) => item.isFav == 1).length;

    final authorCounts = <String, int>{};
    final tagCounts = <String, int>{};
    for (final item in records) {
      final author = item.authorName;
      if (author != null && author.isNotEmpty) {
        authorCounts[author] = (authorCounts[author] ?? 0) + 1;
      }
      final tag = item.tagName;
      if (tag != null && tag.isNotEmpty) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }

    if (authorCounts.isNotEmpty) {
      final topAuthor = authorCounts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      mostWatchedAuthor.value = topAuthor.key;
      mostWatchedAuthorCount.value = topAuthor.value;
    }

    if (tagCounts.isNotEmpty) {
      final topTag = tagCounts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      mostWatchedTag.value = topTag.key;
      mostWatchedTagCount.value = topTag.value;
    }

    final favorite = _findHighlight(records);
    if (favorite != null) {
      favoriteTitle.value = favorite.title ?? '';
      favoriteAuthor.value = favorite.authorName ?? '';
    }
  }

  HistoryItemModel? _findHighlight(Iterable<HistoryItemModel> source) {
    final records = source.toList();
    if (records.isEmpty) return null;

    final favoriteRecords = records.where((item) => item.isFav == 1).toList();
    final candidates = favoriteRecords.isNotEmpty ? favoriteRecords : records;
    candidates.sort((a, b) => _watchedSeconds(b).compareTo(_watchedSeconds(a)));
    return candidates.first;
  }

  String formatWatchDuration() => DurationUtils.formatTimeDuration(
    Duration(seconds: totalWatchedSeconds.value),
  );

  String formatRecordDate(int? timestamp) => DateFormatUtils.format(timestamp);
}
