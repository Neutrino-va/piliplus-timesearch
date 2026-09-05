import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/models/common/search/video_search_type.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:get/get.dart';

/// 「年份回顾」：浏览指定年份内**发布**的视频（区别于「我的回顾」按观看时间）。
///
/// 数据走 B 站分类搜索接口（WBI 签名）。实测（2026-09，小米平板4 真机）：
/// B 站对空关键词返回 -400「请求错误」，因此关键词必填；
/// 发布时间(pubtime) + 分区(tids) + 排序(order) 均为服务端筛选，翻页
/// 由 CommonListController 提供，每次只取一页，避免一次性拉取触发风控。
class YearRecallController
    extends CommonListController<SearchVideoData, SearchVideoItemModel> {
  /// B 站上线时间为 2009 年，更早年份无投稿。
  static final DateTime earliestDate = DateTime(2009, 6, 26);

  final RxInt selectedYear = DateTime.now().year.obs;
  final Rx<VideoZoneType> selectedZone = VideoZoneType.all.obs;

  /// 搜索关键词（B 站接口必填，为空时接口返回 -400 请求错误）。
  final RxString keyword = ''.obs;

  /// 排序参数值：totalrank(综合·热度) / like(点赞) / click(播放) /
  /// stow(收藏) / pubdate(最新发布)。B 站官方枚举未收录 like，
  /// 若服务端忽略该值会退化为默认排序，不影响功能。
  final RxString selectedOrder = 'totalrank'.obs;

  String? gaiaVtoken;

  void setKeyword(String value) {
    final trimmed = value.trim();
    if (keyword.value == trimmed) return;
    keyword.value = trimmed;
    if (trimmed.isNotEmpty) {
      onReload();
    }
  }

  List<int> get availableYears => [
    for (
      int year = DateTime.now().year;
      year >= earliestDate.year;
      year--
    )
      year,
  ];

  int get _beginTs =>
      DateTime(selectedYear.value, 1, 1).millisecondsSinceEpoch ~/ 1000;

  int get _endTs =>
      DateTime(
        selectedYear.value,
        12,
        31,
        23,
        59,
        59,
      ).millisecondsSinceEpoch ~/ 1000;

  void selectYear(int year) {
    if (selectedYear.value == year) return;
    selectedYear.value = year;
    onReload();
  }

  void setZone(VideoZoneType zone) {
    if (selectedZone.value == zone) return;
    selectedZone.value = zone;
    onReload();
  }

  void setOrder(String order) {
    if (selectedOrder.value == order) return;
    selectedOrder.value = order;
    onReload();
  }

  @override
  List<SearchVideoItemModel>? getDataList(SearchVideoData response) =>
      response.list;

  @override
  Future<LoadingState<SearchVideoData>> customGetData() {
    return SearchHttp.searchByType<SearchVideoData>(
      searchType: SearchType.video,
      keyword: keyword.value,
      page: page,
      order: selectedOrder.value,
      tids: selectedZone.value == VideoZoneType.all
          ? null
          : selectedZone.value.tids,
      pubBegin: _beginTs,
      pubEnd: _endTs,
      gaiaVtoken: gaiaVtoken,
      onSuccess: (String token) {
        gaiaVtoken = token;
        queryData(page == 1);
      },
    );
  }
}
