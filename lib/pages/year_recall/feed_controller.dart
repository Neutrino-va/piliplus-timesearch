import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/models_new/popular/popular_series_list/list.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:get/get.dart';

/// 「年份回顾 · 考古推荐流」：无需关键词，按年份聚合 B 站官方「每周必看」
/// 合集（popular/series），还原当年首页热门的浏览体验。
///
/// 每一"页"对应一周的官方精选（约25-30条，覆盖全部分区、时政热点与热门
/// 音乐等内容），下滑自动加载上一周的下一期；B站该合集自2019年前后开始，
/// 更早年份请使用关键词筛选模式。
class YearRecallFeedController
    extends CommonListController<List<HotVideoItemModel>, HotVideoItemModel> {
  final RxInt selectedYear = DateTime.now().year.obs;

  /// 全部每周必看期数（服务端按新→旧返回）。
  List<PopularSeriesListItem>? seriesList;

  /// 当前年份命中的期数（新→旧）。
  List<PopularSeriesListItem>? _yearEditions;

  /// 期数列表是否已就绪（决定年份芯片能否渲染）。
  final RxBool listReady = false.obs;

  bool _seriesListLoading = false;

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
    final result = years.toList()..sort((a, b) => b.compareTo(a));
    return result.isEmpty ? [selectedYear.value] : result;
  }

  bool get hasCurrentYearEditions =>
      _yearEditions != null && _yearEditions!.isNotEmpty;

  Future<void> ensureSeriesList() async {
    if (seriesList != null || _seriesListLoading) return;
    _seriesListLoading = true;
    final res = await VideoHttp.popularSeriesList();
    _seriesListLoading = false;
    if (res case Success(:final response)) {
      seriesList = response;
      listReady.value = true;
      _prepareYearEditions();
      // 期数就绪后拉取第一周，否则页面会停留在加载态。
      queryData();
    } else if (res case Error(:final errMsg)) {
      loadingState.value = Error(errMsg);
      listReady.value = true;
    }
  }

  void selectYear(int year) {
    if (selectedYear.value == year) return;
    selectedYear.value = year;
    _prepareYearEditions();
    onReload();
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
}
