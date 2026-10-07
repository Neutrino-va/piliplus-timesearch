// 「AI 设置助手」:设置注册表 + 指令协议 + 执行器。
//
// 协议:模型在回答文本中内嵌 `<<SET:key=value>>` 指令(可多条),
// 客户端流式展示时剥离指令,结束后统一校验并落盘(见 applySettingDirective)。
// 注册表为精选常用项;账号/存储/网络等敏感项不开放,助手会指引用户手动修改。
import 'package:PiliPlus/models/common/member/tab_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/models/common/theme/theme_type.dart';
import 'package:PiliPlus/models/common/video/audio_quality.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:get/get.dart';

/// 一个可由助手读取/写入的设置项。
class SettingSpec {
  const SettingSpec({
    required this.key,
    required this.title,
    required this.hint,
    required this.options,
    required this.read,
    required this.write,
  });

  /// 指令标识(与 SettingBoxKey 字符串一致)
  final String key;
  final String title;

  /// 给模型的一句说明
  final String hint;

  /// 可选值(供模型写指令);布尔项固定为 开/关,数值项见 hint 范围
  final List<String> options;
  final String Function() read;
  final Future<void> Function(String value) write;
}

const _onOff = ['开', '关'];

bool _parseOnOff(String value) => switch (value.trim()) {
  '开' || 'true' || '1' => true,
  '关' || 'false' || '0' => false,
  _ => throw const FormatException('取值应为 开/关'),
};

double _parseNum(String value, double min, double max) {
  final v = double.tryParse(value.trim());
  if (v == null) throw FormatException('取值应为 $min~$max 内的数字');
  return v.clamp(min, max);
}

int _rawInt(Object? raw, int fallback) =>
    raw is int && raw >= 0 ? raw : fallback;

T _enumFromLabel<T extends Object>(
  List<T> values,
  String label,
  String Function(T) labelOf,
) => values.firstWhere(
  (e) => labelOf(e) == label.trim(),
  orElse: () => throw FormatException('取值应为:${values.map(labelOf).join('/')}'),
);

const _fullScreenLabels = <FullScreenMode, String>{
  FullScreenMode.auto: '按视频方向',
  FullScreenMode.none: '不改变方向',
  FullScreenMode.vertical: '强制竖屏',
  FullScreenMode.horizontal: '强制横屏',
  FullScreenMode.gravity: '按重力转屏',
};

final List<SettingSpec> kAgentSettingSpecs = [
  SettingSpec(
    key: SettingBoxKey.themeMode,
    title: '主题模式',
    hint: '浅色/深色/跟随系统,改完立即生效',
    options: [for (final t in ThemeType.values) t.label],
    read: () => ThemeType
        .values[_rawInt(
          GStorage.setting.get(SettingBoxKey.themeMode),
          ThemeType.system.index,
        )]
        .label,
    write: (value) async {
      final t = _enumFromLabel(ThemeType.values, value, (e) => e.label);
      try {
        Get.find<MineController>().themeType.value = t;
      } catch (_) {}
      await GStorage.setting.put(SettingBoxKey.themeMode, t.index);
      Get.changeThemeMode(ThemeUtils.themeMode = t.toThemeMode);
    },
  ),
  SettingSpec(
    key: SettingBoxKey.dynamicColor,
    title: '动态取色',
    hint: '开启后主题色跟随系统壁纸取色',
    options: _onOff,
    read: () => Pref.dynamicColor ? '开' : '关',
    write: (value) async {
      final v = _parseOnOff(value);
      await GStorage.setting.put(SettingBoxKey.dynamicColor, v);
      Get.updateMyAppTheme();
    },
  ),
  SettingSpec(
    key: SettingBoxKey.defaultTextScale,
    title: '全局字体缩放',
    hint: '0.6~2.0 的数字,如 1.2;重启后完全生效',
    options: const [],
    read: () => Pref.defaultTextScale.toStringAsFixed(2),
    write: (value) async {
      final v = _parseNum(value, 0.6, 2.0);
      await GStorage.setting.put(SettingBoxKey.defaultTextScale, v);
    },
  ),
  SettingSpec(
    key: SettingBoxKey.autoPlayEnable,
    title: '自动播放',
    hint: '进入视频页是否自动开播',
    options: _onOff,
    read: () => Pref.autoPlayEnable ? '开' : '关',
    write: (value) async {
      await GStorage.setting.put(
        SettingBoxKey.autoPlayEnable,
        _parseOnOff(value),
      );
    },
  ),
  SettingSpec(
    key: SettingBoxKey.defaultVideoQa,
    title: '默认画质(WiFi)',
    hint: '如 1080P 高清、4K 超高清',
    options: [for (final q in VideoQuality.values) q.shortDesc],
    read: () => VideoQuality.values
        .firstWhere(
          (e) => e.code == Pref.defaultVideoQa,
          orElse: () => VideoQuality.high1080,
        )
        .shortDesc,
    write: (value) async {
      final qa = _enumFromLabel(
        VideoQuality.values,
        value,
        (e) => e.shortDesc,
      );
      await GStorage.setting.put(SettingBoxKey.defaultVideoQa, qa.code);
    },
  ),
  SettingSpec(
    key: SettingBoxKey.defaultVideoQaCellular,
    title: '默认画质(流量)',
    hint: '移动网络下的默认画质',
    options: [for (final q in VideoQuality.values) q.shortDesc],
    read: () => VideoQuality.values
        .firstWhere(
          (e) => e.code == Pref.defaultVideoQaCellular,
          orElse: () => VideoQuality.high1080,
        )
        .shortDesc,
    write: (value) async {
      final qa = _enumFromLabel(
        VideoQuality.values,
        value,
        (e) => e.shortDesc,
      );
      await GStorage.setting.put(
        SettingBoxKey.defaultVideoQaCellular,
        qa.code,
      );
    },
  ),
  SettingSpec(
    key: SettingBoxKey.defaultAudioQa,
    title: '默认音质(WiFi)',
    hint: '如 Hi-Res无损、杜比全景声、192K',
    options: [
      for (final q in AudioQuality.values)
        if (q.code < 100000) q.desc,
    ],
    read: () => AudioQuality.values
        .firstWhere(
          (e) => e.code == Pref.defaultAudioQa,
          orElse: () => AudioQuality.k192,
        )
        .desc,
    write: (value) async {
      final qa = _enumFromLabel(AudioQuality.values, value, (e) => e.desc);
      await GStorage.setting.put(SettingBoxKey.defaultAudioQa, qa.code);
    },
  ),
  SettingSpec(
    key: SettingBoxKey.fullScreenMode,
    title: '全屏模式',
    hint: '进全屏时的屏幕方向策略',
    options: _fullScreenLabels.values.toList(),
    read: () =>
        _fullScreenLabels[FullScreenMode
            .values[_rawInt(
              GStorage.setting.get(SettingBoxKey.fullScreenMode),
              FullScreenMode.auto.index,
            )]] ??
        '按视频方向',
    write: (value) async {
      final mode = _fullScreenLabels.entries
          .firstWhere(
            (e) => e.value == value.trim(),
            orElse: () => throw const FormatException(
              '取值应为:按视频方向/不改变方向/强制竖屏/强制横屏/按重力转屏',
            ),
          )
          .key;
      await GStorage.setting.put(SettingBoxKey.fullScreenMode, mode.index);
    },
  ),
  SettingSpec(
    key: SettingBoxKey.replySortType,
    title: '评论排序',
    hint: '评论区默认排序方式',
    options: [for (final t in ReplySortType.values) t.label],
    read: () => Pref.replySortType.label,
    write: (value) async {
      final t = _enumFromLabel(ReplySortType.values, value, (e) => e.label);
      await GStorage.setting.put(SettingBoxKey.replySortType, t.index);
    },
  ),
  SettingSpec(
    key: SettingBoxKey.defaultHomePage,
    title: '默认启动页',
    hint: '应用启动时落在哪个底部标签,重启后生效',
    options: [for (final t in NavigationBarType.values) t.label],
    read: () => NavigationBarType
        .values[_rawInt(
          GStorage.setting.get(SettingBoxKey.defaultHomePage),
          NavigationBarType.home.index,
        )]
        .label,
    write: (value) async {
      final t = _enumFromLabel(
        NavigationBarType.values,
        value,
        (e) => e.label,
      );
      await GStorage.setting.put(SettingBoxKey.defaultHomePage, t.index);
    },
  ),
  SettingSpec(
    key: SettingBoxKey.enableAi,
    title: 'B站AI视频总结',
    hint: 'B站官方的 AI 视频总结入口开关(与 AI 设置助手无关)',
    options: _onOff,
    read: () => Pref.enableAi ? '开' : '关',
    write: (value) async {
      await GStorage.setting.put(SettingBoxKey.enableAi, _parseOnOff(value));
    },
  ),
  SettingSpec(
    key: SettingBoxKey.enableSearchWord,
    title: '搜索框热词推荐',
    hint: '首页搜索框显示B站热搜词',
    options: _onOff,
    read: () => Pref.enableSearchWord ? '开' : '关',
    write: (value) async {
      await GStorage.setting.put(
        SettingBoxKey.enableSearchWord,
        _parseOnOff(value),
      );
    },
  ),
  SettingSpec(
    key: SettingBoxKey.disableLikeMsg,
    title: '隐藏「收到的赞」',
    hint: '关闭消息页的收到的赞入口',
    options: _onOff,
    read: () => Pref.disableLikeMsg ? '开' : '关',
    write: (value) async {
      await GStorage.setting.put(
        SettingBoxKey.disableLikeMsg,
        _parseOnOff(value),
      );
    },
  ),
  SettingSpec(
    key: SettingBoxKey.showMemberShop,
    title: '会员购入口',
    hint: '「我的」页是否显示会员购',
    options: _onOff,
    read: () => Pref.showMemberShop ? '开' : '关',
    write: (value) async {
      final v = _parseOnOff(value);
      await GStorage.setting.put(SettingBoxKey.showMemberShop, v);
      MemberTabType.showMemberShop = v;
    },
  ),
  SettingSpec(
    key: SettingBoxKey.enableSponsorBlock,
    title: '空降助手',
    hint: '社区贡献的跳过恰饭片段',
    options: _onOff,
    read: () => Pref.enableSponsorBlock ? '开' : '关',
    write: (value) async {
      await GStorage.setting.put(
        SettingBoxKey.enableSponsorBlock,
        _parseOnOff(value),
      );
    },
  ),
  SettingSpec(
    key: SettingBoxKey.autoUpdate,
    title: '启动检查更新',
    hint: '每次启动时检查是否有新版本',
    options: _onOff,
    read: () => Pref.autoUpdate ? '开' : '关',
    write: (value) async {
      await GStorage.setting.put(
        SettingBoxKey.autoUpdate,
        _parseOnOff(value),
      );
    },
  ),
  SettingSpec(
    key: SettingBoxKey.yearRoamingEnabled,
    title: '年份回顾功能',
    hint: '关闭后隐藏回顾入口并停止回顾数据加载,降低耗电',
    options: _onOff,
    read: () => Pref.yearRoamingEnabled ? '开' : '关',
    write: (value) async {
      final v = _parseOnOff(value);
      await GStorage.setting.put(SettingBoxKey.yearRoamingEnabled, v);
      if (Get.isRegistered<MainController>()) {
        Get.find<MainController>().yearRoamingEnabled.value = v;
      }
    },
  ),
  SettingSpec(
    key: SettingBoxKey.danmakuShowArea,
    title: '弹幕显示区域',
    hint: '0.1~1.0 的数字,弹幕占屏幕高度的比例',
    options: const [],
    read: () => Pref.danmakuShowArea.toStringAsFixed(2),
    write: (value) async {
      await GStorage.setting.put(
        SettingBoxKey.danmakuShowArea,
        _parseNum(value, 0.1, 1.0),
      );
    },
  ),
  SettingSpec(
    key: SettingBoxKey.danmakuFontScale,
    title: '弹幕字号',
    hint: '0.5~2.0 的数字,弹幕文字缩放',
    options: const [],
    read: () => Pref.danmakuFontScale.toStringAsFixed(2),
    write: (value) async {
      await GStorage.setting.put(
        SettingBoxKey.danmakuFontScale,
        _parseNum(value, 0.5, 2.0),
      );
    },
  ),
];

SettingSpec? _findSpec(String key) {
  final k = key.trim();
  for (final s in kAgentSettingSpecs) {
    if (s.key == k) return s;
  }
  return null;
}

final _directiveRe = RegExp(r'<<SET:([^=>]+?)=([^>]*?)>>');

/// 从模型输出中提取全部设置指令 (key, value)。
List<(String, String)> extractSettingDirectives(String text) =>
    _directiveRe
        .allMatches(text)
        .map((m) => (m.group(1)!.trim(), m.group(2)!.trim()))
        .toList();

/// 剥离指令后的展示文本(含流式中尚未闭合的半截指令)。
String stripSettingDirectives(String text) => text
    .replaceAll(_directiveRe, '')
    .replaceAll(RegExp(r'<<SET:[^>]*$'), '');

/// 校验并执行一条指令,返回展示给用户的结果行(✓/✕)。
Future<String> applySettingDirective(String key, String value) async {
  final spec = _findSpec(key);
  if (spec == null) return '✕ 不支持的设置项:$key';
  try {
    await spec.write(value);
    return '✓ ${spec.title} → $value';
  } on FormatException catch (e) {
    return '✕ ${spec.title}:${e.message}';
  } catch (e) {
    return '✕ ${spec.title} 设置失败:$e';
  }
}

/// 组装助手 system prompt:注入注册表(key/名称/当前值/可选值/说明)。
String buildAgentSystemPrompt() {
  final sb = StringBuffer()
    ..writeln('你是「PiliPlus考古版」(一个B站第三方客户端)内置的设置助手。')
    ..writeln('职责:1)用简洁的中文回答用户关于应用设置与功能的问题;'
        '2)当用户想修改设置时,在回答文本中内嵌指令来完成修改。')
    ..writeln()
    ..writeln('## 可操控的设置项(key | 名称 | 当前值 | 可选值 | 说明)');
  for (final s in kAgentSettingSpecs) {
    sb.writeln(
      '- ${s.key} | ${s.title} | ${s.read()} | '
      '${s.options.isEmpty ? '数值(见说明)' : s.options.join('/')} | ${s.hint}',
    );
  }
  sb
    ..writeln()
    ..writeln('## 修改设置的指令格式')
    ..writeln('在回答中单独一行输出 <<SET:key=value>>,可同时多条,'
        '例如把主题改为深色时输出 <<SET:themeMode=深色>>。')
    ..writeln('要求:key 与 value 必须严格来自上面的列表,不得编造;'
        '数值类设置按说明范围取值,如 <<SET:textScale=1.2>>。')
    ..writeln()
    ..writeln('## 其它约定')
    ..writeln('- 用户问「XX在哪设置」时,直接说明路径并给出当前值;'
        '只有用户明确想改时才输出指令。')
    ..writeln('- 超出列表的设置,诚实说明助手暂不支持,'
        '并尽量告知大概在哪个设置分组(基本/隐私/推荐流/音视频/播放器/外观/其它)。')
    ..writeln('- 回答保持简短口语化,不要罗列整个列表。');
  return sb.toString();
}
