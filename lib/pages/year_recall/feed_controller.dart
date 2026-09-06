import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/models_new/popular/popular_series_list/list.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:get/get.dart';

/// 「年份回顾 · 考古推荐流」：按年份浏览当年热门内容。
///
/// - 2019年起（每周必看已上线的年份）：聚合 B 站官方「每周必看」合集
///   （popular/series），每一"页"为一周的官方精选（约25-30条），下滑
///   自动加载上一周。
/// - 更早年份：每周必看尚未上线，自动回退到 B 站官方「入站必刷」经典库
///   （popular/precious），筛选出该年份发布的传世作品，一次性展示。
/// - 分区筛选：基于已加载内容的子分区名（tname）在本地过滤，随翻页动态生效。
class YearRecallFeedController
    extends CommonListController<List<HotVideoItemModel>, HotVideoItemModel> {
  final RxInt selectedYear = DateTime.now().year.obs;

  /// 全部每周必看期数（服务端按新→旧返回）。
  List<PopularSeriesListItem>? seriesList;

  /// 当前年份命中的期数（新→旧）。
  List<PopularSeriesListItem>? _yearEditions;

  /// 入站必刷经典库全量缓存（早年回退数据源）。
  List<HotVideoItemModel>? _preciousAll;

  /// 期数/经典库是否已就绪（决定年份芯片能否渲染）。
  final RxBool listReady = false.obs;

  bool _seriesListLoading = false;
  bool _preciousLoading = false;

  /// 分区筛选（视频子分区名，''=全部）。基于已加载内容本地过滤。
  final RxString selectedTname = ''.obs;

  /// 每周必看覆盖的最早年份；早于该年份走入站必刷回退。
  int? _weeklyStartYear;
  int get weeklyStartYear => _weeklyStartYear ?? DateTime.now().year;

  /// 每周必看覆盖不到的年份（如2009-2018）没有可聚合的期数。
  List<int> get availableYears {
    final years = <int>{};
    for (final edition in seriesList ?? const <PopularSeriesListItem>[]) {
      final name = edition.name;
      if (name == null) continue;
      final idx = name.indexOf('第');
      final year = idx > 0 ? int.tryParse(name.substring(0, idx)) : null;
      if (year != null) years.add(year);
    }
    if (_preciousAll != null) {
      for (final video in _preciousAll!) {
        final pubdate = video.pubdate;
        if (pubdate != null) years.add(_yearOf(pubdate));
      }
    }
    final result = years.toList()..sort((a, b) => b.compareTo(a));
    return result.isEmpty ? [selectedYear.value] : result;
  }

  static int _yearOf(int seconds) =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000).year;

  bool get hasCurrentYearEditions =>
      _yearEditions != null && _yearEditions!.isNotEmpty;

  /// 已加载内容中出现过的子分区名（按出现次数降序）。
  List<String> availableTnames(List<HotVideoItemModel> items) {
    final map = <String, int>{};
    for (final video in items) {
      final tname = video.tname;
      if (tname == null || tname.isEmpty) continue;
      map[tname] = (map[tname] ?? 0) + 1;
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(16)) e.key];
  }

  Future<void> ensureSeriesList() async {
    if (seriesList != null || _seriesListLoading) return;
    _seriesListLoading = true;
    final res = await VideoHttp.popularSeriesList();
    _seriesListLoading = false;
    if (res case Success(:final response)) {
      seriesList = response;
      _weeklyStartYear = _computeWeeklyStartYear();
      _prepareYearEditions();
      listReady.value = true;
      _queryIfValid();
      // 并行加载入站必刷经典库,供早年回退与年份芯片。
      _ensurePrecious();
    } else if (res case Error(:final errMsg)) {
      loadingState.value = Error(errMsg);
      listReady.value = true;
    }
  }

  int _computeWeeklyStartYear() {
    int? minYear;
    for (final edition in seriesList ?? const <PopularSeriesListItem>[]) {
      final name = edition.name;
      if (name == null) continue;
      final idx = name.indexOf('第');
      final year = idx > 0 ? int.tryParse(name.substring(0, idx)) : null;
      if (year != null &&
          (minYear == null || year < minYear) &&
          year > 2000) {
        minYear = year;
      }
    }
    return minYear ?? DateTime.now().year;
  }

  Future<void> _ensurePrecious() async {
    if (_preciousAll != null || _preciousLoading) return;
    _preciousLoading = true;
    final all = <HotVideoItemModel>[];
    for (int page = 1; page <= 10; page++) {
      final res = await VideoHttp.popularPrecious(page: page);
      if (res case Success(:final response)) {
        final list = response.list ?? const <HotVideoItemModel>[];
        all.addAll(list);
        if (list.length < 100) break;
      } else {
        break;
      }
    }
    _preciousAll = all;
  }

  void selectYear(int year) {
    if (selectedYear.value == year) return;
    selectedYear.value = year;
    _prepareYearEditions();
    onReload();
  }

  void setTname(String tname) {
    if (selectedTname.value == tname) return;
    selectedTname.value = tname;
  }

  void _prepareYearEditions() {
    _yearEditions = (seriesList ?? const <PopularSeriesListItem>[])
        .where(
          (edition) =>
              edition.name?.startsWith('${selectedYear.value}第') == true &&
              edition.number != null,
        )
        .toList();
  }

  @override
  List<HotVideoItemModel>? getDataList(List<HotVideoItemModel> response) =>
      response;

  @override
  Future<LoadingState<List<HotVideoItemModel>>> customGetData() async {
    // 早于每周必看上线年份：入站必刷经典库按年过滤,一次性返回(page>1为空)。
    if (selectedYear.value < weeklyStartYear) {
      await _ensurePrecious();
      final all = _preciousAll ?? const <HotVideoItemModel>[];
      final filtered = all
          .where((video) => _yearOf(video.pubdate ?? 0) == selectedYear.value)
          .toList();
      return page == 1 ? Success(filtered) : const Success([]);
    }

    final editions = _yearEditions ?? const <PopularSeriesListItem>[];
    final index = page - 1;
    if (index >= editions.length) {
      isEnd = true;
      return const Success([]);
    }
    final res = await VideoHttp.popularSeriesOne(
      number: editions[index].number!,
    );
    switch (res) {
      case Success(:final response):
        return Success(response.list ?? <HotVideoItemModel>[]);
      case Error(:final errMsg, :final code):
        return Error(errMsg, code: code);
      default:
        return const Error(null);
    }
  }

  void _queryIfValid() {
    // 年份芯片依赖期数/经典库就绪后再触发首查,避免命中空数据。
    if (_yearEditions == null) _prepareYearEditions();
    queryData();
  }
}

