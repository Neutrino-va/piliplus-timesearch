import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/models_new/history/tab.dart';

class HistoryData {
  HistoryCursor? cursor;
  List<HistoryTab>? tab;
  List<HistoryItemModel>? list;

  HistoryData({this.cursor, this.tab, this.list});

  factory HistoryData.fromJson(Map<String, dynamic> json) {
    // cursor 容器不做严格泛型判定，避免 Map<dynamic, dynamic> 被误判为缺失
    final rawCursor = json['cursor'];
    return HistoryData(
      cursor: rawCursor is Map
          ? HistoryCursor.fromJson(Map<String, dynamic>.from(rawCursor))
          : null,
      tab: (json['tab'] as List<dynamic>?)
          ?.map((e) => HistoryTab.fromJson(e as Map<String, dynamic>))
          .toList(),
      list: (json['list'] as List<dynamic>?)
          ?.map((e) => HistoryItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class HistoryCursor {
  int? max;
  int? viewAt;
  String? business;
  int? ps;

  HistoryCursor({this.max, this.viewAt, this.business, this.ps});

  // 兼容服务端把数值序列化为 int / num / 字符串的情况，解析失败返回 null 而不是抛异常
  static int? _asInt(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };

  factory HistoryCursor.fromJson(Map<String, dynamic> json) => HistoryCursor(
    max: _asInt(json['max']),
    viewAt: _asInt(json['view_at']),
    business: json['business'] is String ? json['business'] as String : null,
    ps: _asInt(json['ps']),
  );
}
