import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:material_ui/material_ui.dart';

/// 「偏好词云」:从观看记录与搜索历史中统计高频词,按权重渲染为词云卡片。
///
/// 词源(合并去重):
/// - 标题关键词:中文 2-4 字 n-gram + 英文单词,按出现视频数(文档频)统计,
///   经停用词与子串去重——经典词频统计,无需 AI/分词库;
/// - 常看 UP 主、内容分区:按出现条数计权;
/// - 搜索词:本应用内的搜索历史(cacheList,仅去重无频次,给基础权重)。
class CloudWord {
  const CloudWord(this.text, this.weight, this.source);

  final String text;
  final int weight;

  /// title=标题关键词 up=UP主 zone=分区 search=搜索词
  final String source;
}

final RegExp _cjkRun = RegExp(r'[\u4e00-\u9fff]{2,}');
final RegExp _latinWord = RegExp(r'[A-Za-z][A-Za-z0-9]{1,}');

/// 停用词:高频但无信息量的组合词与视频行业套话。
const Set<String> _stopWords = {
  '一个',
  '没有',
  '我们',
  '你们',
  '他们',
  '这个',
  '那个',
  '什么',
  '已经',
  '可以',
  '就是',
  '不是',
  '自己',
  '还是',
  '但是',
  '因为',
  '所以',
  '如果',
  '这是',
  '真的',
  '现在',
  '时候',
  '知道',
  '觉得',
  '感觉',
  '开始',
  '最后',
  '终于',
  '居然',
  '竟然',
  '这么',
  '那么',
  '如何',
  '为什么',
  '怎么样',
  '一下',
  '一样',
  '上来',
  '出来',
  '起来',
  '过去',
  '回来',
  '一群',
  '一只',
  '史上',
  '全网',
  '国内',
  '国外',
  '最新',
  '最全',
  '超全',
  '完整',
  '完整体',
  '完整版',
  '正式版',
  '最新版',
  '最终版',
  '年度',
  '年终',
  '盘点',
  '合集',
  '教程',
  '视频',
  '全集',
  '首发',
  '独家',
  '重磅',
  '正版',
  '更新',
  '上线',
  '发布',
  '体验',
  '试玩',
  '实况',
  '直播',
  '回放',
  '第一期',
  '第二期',
  '第三期',
  '第四期',
  '上半',
  '下半',
  '关于',
  '之后',
  '这些',
  '哪些',
  '以及',
  '并且',
  '不过',
  '只是',
  '还有',
  '来说',
  '第一',
  '第二',
  '第三',
  '第四',
  '第五',
  '第六',
  '第七',
  '第八',
  '第九',
  '第十',
};

/// 从观看记录与搜索历史挖掘偏好词,按权重降序返回最多 [limit] 个。
List<CloudWord> mineWords(
  List<HistoryItemModel> records,
  List<String> searchTerms, {
  int limit = 36,
}) {
  if (records.isEmpty && searchTerms.isEmpty) return const [];

  // ---- 标题关键词:n-gram 文档频 ----
  final Map<String, int> gramDf = {};
  final Map<String, int> latinDf = {};

  // ---- UP 主 / 分区 ----
  final Map<String, int> upCount = {};
  final Map<String, int> zoneCount = {};

  for (final item in records) {
    final title = item.title ?? '';
    final grams = <String>{};
    for (final run in _cjkRun.allMatches(title)) {
      final text = run.group(0)!;
      for (final n in const [2, 3, 4]) {
        if (text.length < n) continue;
        for (int i = 0; i + n <= text.length; i++) {
          grams.add(text.substring(i, i + n));
        }
      }
    }
    for (final gram in grams) {
      if (!_stopWords.contains(gram)) {
        gramDf[gram] = (gramDf[gram] ?? 0) + 1;
      }
    }
    for (final word in _latinWord.allMatches(title)) {
      final text = word.group(0)!;
      latinDf[text] = (latinDf[text] ?? 0) + 1;
    }

    final author = item.authorName;
    if (author != null && author.isNotEmpty) {
      upCount[author] = (upCount[author] ?? 0) + 1;
    }
    final zone = item.tagName;
    if (zone != null && zone.isNotEmpty) {
      zoneCount[zone] = (zoneCount[zone] ?? 0) + 1;
    }
  }

  // ---- 组装候选词(文档频≥3 的标题词;英文≥2) ----
  final List<CloudWord> candidates = [];
  void addAll(Map<String, int> df, String source, int minDf) {
    df.forEach((text, df) {
      if (df >= minDf && text.length >= 2) {
        candidates.add(CloudWord(text, df, source));
      }
    });
  }

  addAll(gramDf, 'title', 3);
  addAll(latinDf, 'title', 2);
  upCount.forEach((text, count) {
    candidates.add(CloudWord(text, count, 'up'));
  });
  zoneCount.forEach((text, count) {
    candidates.add(CloudWord(text, count, 'zone'));
  });

  // 子串去重:若长词覆盖短词且文档频不低于短词,丢弃短词。
  candidates.sort((a, b) {
    final byDf = b.weight.compareTo(a.weight);
    return byDf != 0 ? byDf : b.text.length.compareTo(a.text.length);
  });
  final kept = <CloudWord>[];
  for (final candidate in candidates) {
    final covered = kept.any(
      (k) =>
          k.text.length > candidate.text.length &&
          k.text.contains(candidate.text) &&
          k.weight >= candidate.weight,
    );
    if (!covered) kept.add(candidate);
  }

  // ---- 搜索词:基础权重 2,与已挖掘词合并加成 ----
  final seenSearch = <String>{};
  for (final term in searchTerms) {
    final text = term.trim();
    if (text.length < 2 || !seenSearch.add(text)) continue;
    final idx = kept.indexWhere((k) => k.text == text);
    if (idx >= 0) {
      kept[idx] = CloudWord(
        kept[idx].text,
        kept[idx].weight + 2,
        kept[idx].source,
      );
    } else if (kept.length < limit * 2) {
      kept.add(CloudWord(text, 2, 'search'));
    }
  }

  // 同词异源合并(MAX 权重,来源优先级 up > zone > search > title)
  final merged = <String, CloudWord>{};
  int sourceRank(String source) => switch (source) {
    'up' => 3,
    'zone' => 2,
    'search' => 1,
    _ => 0,
  };
  for (final word in kept) {
    final existing = merged[word.text];
    if (existing == null) {
      merged[word.text] = word;
    } else {
      final preferNew =
          word.weight > existing.weight ||
          (word.weight == existing.weight &&
              sourceRank(word.source) > sourceRank(existing.source));
      merged[word.text] = preferNew ? word : existing;
    }
  }

  final result = merged.values.toList()
    ..sort((a, b) {
      final byWeight = b.weight.compareTo(a.weight);
      return byWeight != 0 ? byWeight : b.text.length.compareTo(a.text.length);
    });
  return result.take(limit).toList();
}

/// 偏好词云卡片:样式与分区统计卡同源,点击词条触发筛选回调。
class WordCloudCard extends StatelessWidget {
  const WordCloudCard({
    super.key,
    required this.colorScheme,
    required this.records,
    required this.searchTerms,
    required this.currentFilter,
    required this.onToggle,
  });

  final ColorScheme colorScheme;
  final List<HistoryItemModel> records;
  final List<String> searchTerms;
  final String currentFilter;
  final void Function(String word) onToggle;

  @override
  Widget build(BuildContext context) {
    final words = mineWords(records, searchTerms);
    if (words.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: Style.mdRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              Text(
                '偏好词云',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '基于 ${records.length} 条记录与搜索历史',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            ],
          ),
          Text(
            '字号越大代表出现越多;点击词条可筛选下方列表。',
            style: TextStyle(fontSize: 11, color: colorScheme.outline),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in words.asMap().entries)
                _WordChip(
                  word: entry.value,
                  fontSize: 22.0 -
                      ((entry.key / words.length) * 10).round().toDouble(),
                  selected: currentFilter == entry.value.text,
                  colorScheme: colorScheme,
                  onTap: () => onToggle(entry.value.text),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.fontSize,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
  });

  final CloudWord word;
  final double fontSize;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (word.source) {
      'up' => colorScheme.tertiary,
      'zone' => colorScheme.secondary,
      'search' => colorScheme.primary.withValues(alpha: 0.8),
      _ => colorScheme.primary,
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 8 + (fontSize - 12) * 0.5,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.secondaryContainer.withValues(alpha: 0.9)
              : colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: colorScheme.primary.withValues(alpha: 0.6))
              : null,
        ),
        child: Text(
          word.text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontSize > 16 ? FontWeight.bold : FontWeight.w600,
            color: selected ? colorScheme.onSecondaryContainer : accent,
          ),
        ),
      ),
    );
  }
}
