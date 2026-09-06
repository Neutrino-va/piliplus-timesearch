import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart' hide TextStyle;
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/models_new/msg/msg_like/item.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

/// 「我的回顾」· 我的评论获赞排行。
///
/// 主数据源:B站消息中心「收到的赞」(x/msgfeed/like,需登录)——
/// 官方按内容聚合的全部历史获赞(评论/视频/动态等),数据真实完整,按
/// cursor 分页加载。辅助数据源:本应用内发送的评论(本地记录),支持逐条
/// 刷新实时获赞(seek_rpid 定位)。B站无历史弹幕聚合接口,弹幕仅在收到
/// 过赞时出现在消息流中。
class MyLikesRankCard extends StatefulWidget {
  const MyLikesRankCard({super.key});

  @override
  State<MyLikesRankCard> createState() => _MyLikesRankCardState();
}

class _MyLikesRankCardState extends State<MyLikesRankCard> {
  static const int _showCount = 12;
  static const int _autoPages = 2;

  // ---- 收到的赞(消息流,主数据源) ----
  final List<MsgLikeItem> _feedItems = [];
  int? _cursor;
  int? _cursorTime;
  bool _likeEnd = false;
  bool _likeLoading = false;
  bool _likeLoaded = false;
  String? _likeError;
  String _feedFilter = ''; // business 过滤,''=全部

  // ---- 本应用发送的评论(本地,辅助) ----
  List<ReplyInfo> _localReplies = const [];
  bool _localRefreshing = false;
  int _localDone = 0;

  @override
  void initState() {
    super.initState();
    _loadLocal();
    for (int i = 0; i < _autoPages; i++) {
      _loadLikeFeed();
    }
  }

  void _loadLocal() {
    final box = GStorage.reply;
    if (box == null) return;
    _localReplies = box.values.map(ReplyInfo.fromBuffer).toList()
      ..sort((a, b) => b.like.compareTo(a.like));
  }

  Future<void> _loadLikeFeed() async {
    if (_likeLoading || _likeEnd) return;
    _likeLoading = true;
    _likeError = null;
    if (mounted) setState(() {});
    final res = await MsgHttp.msgFeedLikeMe(
      cursor: _cursor,
      cursorTime: _cursorTime,
    );
    if (res case Success(:final response)) {
      final items = [
        ...(response.latest?.items ?? const <MsgLikeItem>[]),
        ...(response.total?.items ?? const <MsgLikeItem>[]),
      ];
      for (final item in items) {
        final business = item.item?.business ?? '';
        final idx = _feedItems.indexWhere(
          (e) =>
              e.item?.business == business &&
              (e.item?.nativeUri == item.item?.nativeUri ||
                  e.item?.title == item.item?.title),
        );
        if (idx < 0) {
          _feedItems.add(item);
        } else if ((item.counts ?? 0) > (_feedItems[idx].counts ?? 0)) {
          _feedItems[idx] = item;
        }
      }
      _cursor = response.total?.cursor?.id;
      _cursorTime = response.total?.cursor?.time;
      _likeEnd = response.total?.cursor?.isEnd == true || items.isEmpty;
      _likeLoaded = true;
    } else if (res case Error(:final errMsg, :final code)) {
      final rateLimited =
          code == 412 || code == 429 || code == -352 || code == -1200;
      _likeError = rateLimited
          ? '被B站限流了，请几分钟后再试（code $code）'
          : errMsg;
      _likeLoaded = true;
    }
    _likeLoading = false;
    if (mounted) setState(() {});
  }

  List<MsgLikeItem> get _rankedFeed {
    final items = _feedFilter.isEmpty
        ? _feedItems
        : _feedItems.where((e) => e.item?.business == _feedFilter).toList();
    return items
      ..sort((a, b) => (b.counts ?? 0).compareTo(a.counts ?? 0));
  }

  List<String> get _feedBusinesses {
    final set = <String>{};
    for (final item in _feedItems) {
      final business = item.item?.business;
      if (business != null && business.isNotEmpty) set.add(business);
    }
    return set.toList();
  }

  // ---- 本应用发送的评论(本地)点赞刷新(seek_rpid 定位) ----

  Future<void> _refreshLocalLikes() async {
    if (_localRefreshing) return;
    final box = GStorage.reply;
    if (box == null || _localReplies.isEmpty) return;
    setState(() {
      _localRefreshing = true;
      _localDone = 0;
    });
    for (final reply in _localReplies) {
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
      _localDone++;
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 150));
    }
    _loadLocal();
    if (mounted) setState(() => _localRefreshing = false);
  }

  /// 通过 seek_rpid 定位原评论,返回当前获赞数;找不到(如被删除)返回 null。
  Future<int?> _fetchLike(ReplyInfo reply) async {
    try {
      final dynamic res;
      if (reply.root.toInt() == 0) {
        // 根评论:主评论列表 seek 定位
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

  void _openContent(MsgLikeItem item) {
    final uri = item.item?.nativeUri;
    if (uri != null && uri.isNotEmpty && !uri.startsWith('?')) {
      PiliScheme.routePushFromUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Text(
                '数据来自B站「收到的赞」（需登录）',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          ..._buildLikeFeed(theme),
          ..._buildLocalSection(theme),
        ],
      ),
    );
  }

  // ---------------- 收到的赞排行(主数据源) ----------------

  List<Widget> _buildLikeFeed(ThemeData theme) {
    if (_likeLoading && _feedItems.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    if (_likeError != null && _feedItems.isEmpty) {
      return [
        Text(
          _likeError!,
          style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
        ),
      ];
    }
    if (_likeLoaded && _feedItems.isEmpty) {
      return [
        Text(
          '暂无收到的赞记录',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
        ),
      ];
    }

    final ranked = _rankedFeed;
    final businesses = _feedBusinesses;
    final shown = ranked.take(_showCount).toList();

    return [
      if (businesses.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              _chip(theme, '全部', _feedFilter.isEmpty, () {
                setState(() => _feedFilter = '');
              }),
              for (final business in businesses)
                _chip(theme, business, _feedFilter == business, () {
                  setState(() => _feedFilter = business);
                }),
            ],
          ),
        ),
      for (final entry in shown.asMap().entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openContent(entry.value),
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
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.value.item?.business ?? '内容',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.thumb_up_alt_rounded,
                      size: 13,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${entry.value.counts ?? 0}',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  entry.value.item?.title ?? '(无标题内容)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                if ((entry.value.users?.isNotEmpty ?? false))
                  Text(
                    '${entry.value.users!.first.nickname} 等'
                    '${entry.value.users!.length} 人觉得很赞',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (ranked.length > _showCount || !_likeEnd)
        Center(
          child: TextButton(
            onPressed: _likeLoading ? null : () => _loadLikeFeed(),
            child: Text(
              _likeLoading
                  ? '加载中…'
                  : ranked.length > _showCount
                  ? '加载更多（当前展示 $_showCount 条）'
                  : '加载更多',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
    ];
  }

  Widget _chip(
    ThemeData theme,
    String text,
    bool selected,
    VoidCallback onTap,
  ) {
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.onInverseSurface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: selected
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- 本应用发送的评论(本地,辅助) ----------------

  List<Widget> _buildLocalSection(ThemeData theme) {
    final hasData = _localReplies.isNotEmpty;
    return [
      const SizedBox(height: 4),
      Row(
        children: [
          Text(
            '本应用发送的评论（本地记录）',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_localRefreshing)
            Text(
              '刷新中 $_localDone/${_localReplies.length}',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.outline,
              ),
            )
          else
            IconButton(
              tooltip: '刷新本地评论的实时获赞(逐条查询,耗时较长)',
              onPressed: hasData ? _refreshLocalLikes : null,
              icon: const Icon(Icons.refresh, size: 18),
            ),
        ],
      ),
      if (!hasData)
        Text(
          '在本应用内发送评论后会自动记录；历史评论可在「我的评论」页导出后导入迁移。',
          style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
        )
      else
        for (final entry in _localReplies.asMap().entries.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: entry.value.type.toInt() == 1
                  ? () => PiliScheme.videoPush(
                      entry.value.oid.toInt(),
                      null,
                      showDialog: false,
                    )
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.thumb_up_alt_rounded,
                          size: 11,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${entry.value.like}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value.content.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
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
            ),
          ),
    ];
  }
}
