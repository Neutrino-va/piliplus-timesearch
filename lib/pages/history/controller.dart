import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models_new/history/data.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/models_new/history/tab.dart';
import 'package:PiliPlus/pages/common/multi_select/multi_select_controller.dart';
import 'package:PiliPlus/pages/history/base_controller.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HistoryController
    extends MultiSelectController<HistoryData, HistoryItemModel>
    with GetSingleTickerProviderStateMixin {
  HistoryController(this.type);

  late final baseCtr = Get.put(HistoryBaseController());

  Account get account => baseCtr.account;

  final String? type;
  TabController? tabController;
  late RxList<HistoryTab> tabs = <HistoryTab>[].obs;

  int? max;
  int? viewAt;
  String? business;

  @override
  RxInt get rxCount => baseCtr.checkedCount;

  @override
  RxBool get enableMultiSelect => baseCtr.enableMultiSelect;

  @override
  void onInit() {
    super.onInit();
    historyStatus();
    queryData();
  }

  @override
  Future<void> onRefresh() {
    max = null;
    viewAt = null;
    business = null;
    return super.onRefresh();
  }

  @override
  List<HistoryItemModel>? getDataList(HistoryData response) {
    return response.list;
  }

  @override
  bool customHandleResponse(bool isRefresh, Success<HistoryData> response) {
    HistoryData data = response.response;
    isEnd = data.list.isNullOrEmpty;
    // 下一页游标只能整体来自服务端返回的 cursor；
    // 禁止用列表末项的 oid/viewAt/business 拼造游标（字段级混合会生成
    // 服务端从未下发过的游标组合，导致 400 / 服务器异常）。
    final cursor = data.cursor;
    if (cursor?.max != null && cursor?.viewAt != null) {
      max = cursor!.max;
      viewAt = cursor.viewAt;
      business = cursor.business;
    } else {
      // 游标缺失或不完整：停止翻页，而不是伪造游标继续请求
      max = null;
      viewAt = null;
      business = null;
      isEnd = true;
    }

    if (isRefresh && type == null) {
      if (tabs.isEmpty && data.tab?.isNotEmpty == true) {
        tabs.value = data.tab!;
        tabController = TabController(
          length: data.tab!.length + 1,
          vsync: this,
        );
      }
    }

    return false;
  }

  // 观看历史暂停状态
  Future<void> historyStatus() async {
    final res = await UserHttp.historyStatus(account: account);
    if (res case Success(:final response)) {
      baseCtr.pauseStatus.value = response;
      GStorage.localCache.put(LocalCacheKey.historyPause, response);
    } else {
      res.toast();
    }
  }

  // 删除某条历史记录
  void delHistory(HistoryItemModel item) {
    _onDelete({item});
  }

  // 删除已看历史记录
  void onDelViewedHistory() {
    final viewedList = loadingState.value.dataOrNull
        ?.where((e) => e.progress == -1)
        .toSet();
    if (viewedList != null && viewedList.isNotEmpty) {
      _onDelete(viewedList);
    } else {
      SmartDialog.showToast('无已看记录');
    }
  }

  Future<void> _onDelete(Set<HistoryItemModel> removeList) async {
    SmartDialog.showLoading(msg: '请求中');
    final res = await UserHttp.delHistory(
      removeList
          .map((item) => '${item.history.business}_${item.kid}')
          .join(','),
      account: account,
    );
    SmartDialog.dismiss();
    if (res.isSuccess) {
      afterDelete(removeList);
      SmartDialog.showToast('已删除');
    } else {
      res.toast();
    }
  }

  // 删除选中的记录
  @override
  void onRemove() {
    showConfirmDialog(
      context: Get.context!,
      title: const Text('提示'),
      content: const Text('确认删除所选历史记录吗？'),
      onConfirm: () => _onDelete(allChecked.toSet()),
    );
  }

  @override
  Future<LoadingState<HistoryData>> customGetData() => UserHttp.historyList(
    type: type ?? 'all',
    max: max,
    viewAt: viewAt,
    business: business,
    account: account,
  );

  @override
  void onClose() {
    tabController?.dispose();
    super.onClose();
  }

  @override
  Future<void> onReload() {
    scrollController.jumpToTop();
    return super.onReload();
  }
}
