import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart' hide TextStyle;
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

/// 「我的回顾」· 我的评论获赞排行(小黑盒风格卡片)。
///
/// 数据源:本应用内发送过的评论(本地 reply 存储)。B站未提供历史评论/弹幕
/// 的聚合查询接口,因此:
/// - 仅能统计「在本应用内发送」的评论(旧记录可通过「我的评论」页导出/导入迁移);
/// - 点赞数为发送时快照,点「刷新」逐条通过 seek_rpid 定位原评论更新获赞;
/// - 弹幕无聚合接口且未做本地记录,暂无法统计,界面上如实标注。
class MyLikesRankCard extends StatefulWidget {
  const MyLikesRankCard({super.key});

  @override
  State<MyLikesRankCard> createState() => _MyLikesRankCardState();
}

class _MyLikesRankCardState extends State<MyLikesRankCard> {
  static const int _showCount = 10;

  List<ReplyInfo> _replies = const [];
  bool _refreshing = false;
  int _done = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final box = GStorage.reply;
    if (box == null) return;
    _replies = box.values.map(ReplyInfo.fromBuffer).toList()
      ..sort((a, b) => b.like.compareTo(a.like));
  }

  Future<void> _refreshLikes() async {
    if (_refreshing) return;
    final box = GStorage.reply;
    if (box == null || box.isEmpty) return;
    setState(() {
      _refreshing = true;
      _done = 0;
    });
    for (final reply in _replies) {
      final like = await _fetchLike(reply);
      if (like != null) {
        reply.like = Int64(like);
        try {
          box.put(
            reply.id.toString(),
            (reply.deepCopy()
                  ..unknownFields.clear()
                  ..clearTrackInfo())
                .writeToBuffer(),
          );
        } catch (_) {}
      }
      _done++;
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 150));
    }
    _load();
    if (mounted) setState(() => _refreshing = false);
  }

  /// 通过 seek_rpid 定位原评论,返回当前获赞数;找不到(如被删除)返回 null。
  Future<int?> _fetchLike(ReplyInfo reply) async {
    try {
      final dynamic res;
      if (reply.root.toInt() == 0) {
        // 根评论:主评论列表定位
        res = await Request().get(
          Api.replyMain,
          queryParameters: {
            'oid': reply.oid.toInt(),
            'type': reply.type.toInt(),
            'mode': 3,
            'plat': 1,
            'web_location': 1315875,
            'seek_rpid': reply.id.toInt(),
            'pagination_str': '{"offset":""}',
          },
        );
      } else {
        // 楼中楼:拉取根评论的子回复列表
        res = await Request().get(
          Api.replyReplyList,
          queryParameters: {
            'oid': reply.oid.toInt(),
            'type': reply.type.toInt(),
            'root': reply.root.toInt(),
            'ps': 49,
          },
        );
      }
      final replies = res.data?['data']?['replies'] as List?;
      if (replies == null) return null;
      for (final item in replies) {
        if (item is Map && item['rpid']?.toString() == reply.id.toString()) {
          final like = item['like'];
          return like is int ? like : int.tryParse('$like');
        }
      }
    } catch (_) {}
    return null;
  }

  void _openVideo(ReplyInfo reply) {
    if (reply.type.toInt() == 1) {
      // 视频评论:跳转对应视频
      PiliScheme.videoPush(reply.oid.toInt(), null, showDialog: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = _replies.isNotEmpty;
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
        spacing: 10,
        children: [
          Row(
            children: [
              Text(
                '我的评论获赞排行',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_refreshing)
                Text(
                  '刷新中 $_done/${_replies.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.outline,
                  ),
                )
              else
                IconButton(
                  tooltip: '刷新点赞数据(逐条查询,评论较多时耗时较长)',
                  onPressed: _refreshLikes,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
          Text(
            hasData
                ? '统计本应用内发送的 ${_replies.length} 条评论的获赞。'
                    'B站未提供历史弹幕聚合接口，弹幕暂无法统计。'
                : '暂无记录：在本应用内发送评论后会自动记录用于排行'
                    '（旧版记录可在「我的评论」页导出后导入迁移）。'
                    'B站未提供弹幕聚合查询接口，弹幕暂无法统计。',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
          ),
          if (hasData)
            for (final entry in _replies.asMap().entries.take(_showCount))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openVideo(entry.value),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${entry.key + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.outline,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.thumb_up_alt_rounded,
                            size: 13,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${entry.value.like}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            DateFormatUtils.chatFormat(
                              entry.value.ctime.toInt(),
                              isHistory: true,
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        entry.value.content.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
          if (_replies.length > _showCount)
            Text(
              '仅展示获赞最高的 $_showCount 条，共 ${_replies.length} 条',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }
}
