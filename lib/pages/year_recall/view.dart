import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/skeleton/video_card_h.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/search/video_search_type.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/pages/year_recall/controller.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 「年份回顾」区段：以 slivers 形式嵌入年份漫游页的 CustomScrollView。
/// 排序/分区/年份切换均即时重查，分页为滚动到底自动加载下一页。
abstract final class YearRecallView {
  static final _gridDelegate = Grid.videoCardHDelegate();

  /// 排序选项：(展示名, 搜索接口 order 值)。
  static const List<(String, String)> _orders = [
    ('综合·热度', 'totalrank'),
    ('最多点赞', 'like'),
    ('最多播放', 'click'),
    ('最多收藏', 'stow'),
    ('最新发布', 'pubdate'),
  ];

  static List<Widget> buildSlivers(
    ThemeData theme,
    YearRecallController controller,
  ) {
    return [
      SliverToBoxAdapter(child: _buildKeywordBar(theme, controller)),
      SliverToBoxAdapter(child: _buildYearPicker(theme, controller)),
      SliverToBoxAdapter(child: _buildFilterRow(theme, controller)),
      ..._buildContent(theme, controller),
    ];
  }

  /// 关键词输入栏。实测 B 站搜索接口对空关键词返回 -400「请求错误」，
  /// 因此「年份回顾」需要关键词配合年份/分区/排序浏览。
  static Widget _buildKeywordBar(
    ThemeData theme,
    YearRecallController controller,
  ) => _KeywordBar(controller: controller);

  static Widget _chip({
    required ThemeData theme,
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    // 选中态由父级 Obx 统一重建，这里不再包 Obx（内部无响应式读取）。
    return SearchText(
      text: text,
      onTap: (_) => onTap(),
      bgColor: selected ? theme.colorScheme.secondaryContainer : null,
      textColor: selected ? theme.colorScheme.onSecondaryContainer : null,
    );
  }

  static Widget _buildYearPicker(
    ThemeData theme,
    YearRecallController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '选择年份（按发布时间）',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${controller.selectedYear.value} 年投稿',
                style: TextStyle(color: theme.colorScheme.primary),
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
                  text: '📅 日历',
                  bgColor: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  onTap: (_) async {
                    final picked = await showDatePicker(
                      context: Get.context!,
                      initialDate: DateTime(controller.selectedYear.value, 1, 1),
                      firstDate: YearRecallController.earliestDate,
                      lastDate: DateTime.now(),
                      helpText: '选择年份（任选日期后取其年份）',
                      cancelText: '取消',
                      confirmText: '确定',
                    );
                    if (picked != null) {
                      controller.selectYear(picked.year);
                    }
                  },
                ),
                for (final year in controller.availableYears)
                  _chip(
                    theme: theme,
                    text: '$year',
                    selected: controller.selectedYear.value == year,
                    onTap: () => controller.selectYear(year),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildFilterRow(
    ThemeData theme,
    YearRecallController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                Text('排序', style: TextStyle(color: theme.colorScheme.outline)),
                for (final (label, order) in _orders)
                  _chip(
                    theme: theme,
                    text: label,
                    selected: controller.selectedOrder.value == order,
                    onTap: () => controller.setOrder(order),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                Text('分区', style: TextStyle(color: theme.colorScheme.outline)),
                for (final zone in VideoZoneType.values)
                  _chip(
                    theme: theme,
                    text: zone.label,
                    selected: controller.selectedZone.value == zone,
                    onTap: () => controller.setZone(zone),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<Widget> _buildContent(
    ThemeData theme,
    YearRecallController controller,
  ) {
    // 关键词为空时不发起请求（B 站接口必填关键词），展示引导提示。
    if (controller.keyword.value.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 64),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.video_library_outlined,
                  size: 56,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  '输入关键词开始年份浏览',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'B 站接口要求搜索必须带关键词：输入任意关键词后，'
                  '即可按上方年份、分区与排序浏览该年份内发布的投稿，'
                  '下滑自动加载下一页。',
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return switch (controller.loadingState.value) {
      Loading() => [
        SliverGrid(
          gridDelegate: _gridDelegate,
          delegate: SliverChildBuilderDelegate(
            (context, index) => const VideoCardHSkeleton(),
            childCount: 10,
          ),
        ),
      ],
      Success<List<SearchVideoItemModel>?>(:final response) =>
        response == null || response.isEmpty
            ? [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 64),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.video_library_outlined,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${controller.selectedYear.value} 年该分区暂无检索结果',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '可尝试切换分区、更换排序，或选择其他年份。',
                          style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ]
            : [
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8),
                  sliver: SliverGrid.builder(
                    gridDelegate: _gridDelegate,
                    itemBuilder: (context, index) {
                      if (index == response.length - 1) {
                        controller.onLoadMore();
                      }
                      return VideoCardH(videoItem: response[index]);
                    },
                    itemCount: response.length,
                  ),
                ),
              ],
      Error(:final errMsg) => [
        HttpError(errMsg: errMsg, onReload: controller.onReload),
      ],
    };
  }
}

/// 关键词输入行：回车或点「搜索」提交。
class _KeywordBar extends StatefulWidget {
  const _KeywordBar({required this.controller});

  final YearRecallController controller;

  @override
  State<_KeywordBar> createState() => _KeywordBarState();
}

class _KeywordBarState extends State<_KeywordBar> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.keyword.value,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit(String value) => widget.controller.setKeyword(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: TextField(
              controller: _text,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: '输入关键词，浏览其在所选年份的投稿',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          SearchText(
            text: '搜索',
            bgColor: theme.colorScheme.secondaryContainer,
            textColor: theme.colorScheme.onSecondaryContainer,
            onTap: (_) => _submit(_text.text),
          ),
        ],
      ),
    );
  }
}
