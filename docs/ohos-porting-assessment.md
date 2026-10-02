# PiliPlus考古版 · 鸿蒙(OpenHarmony/HarmonyOS)移植可行性评估报告

> 评估时间:2026-09-30 ｜ 评估对象:本项目(PiliPlus考古版,基于 PiliPlus 二开,Flutter 3.47.2)  
> 评估标的:GitCode [CPF-Flutter/flutter_flutter](https://gitcode.com/CPF-Flutter/flutter_flutter)(OpenHarmony SIG 官方 Flutter 移植版 SDK)

---

## 一、结论先行

| 问题 | 结论 |
|---|---|
| 技术上能否移植? | **可行**。OHOS Flutter SDK、media_kit 鸿蒙适配、社区插件适配仓均存在 |
| 工程量? | **数周级 + 持续维护成本**,非一次性工作 |
| 现在应该做吗? | **短期不建议**。版本鸿沟(见下)未解决;且若目标设备是 HarmonyOS 4.x 及以下,**现有 APK 直接可用,零移植** |
| 什么时候值得做? | ① 确认目标设备为 HarmonyOS NEXT(5.x,不能装 APK);② 且 OHOS Flutter 分支跟进到 ≥3.47(消除语法回改) |

---

## 二、目标设备判定(最重要的前置问题)

| 设备系统 | 能否安装现有 APK | 是否需要移植 |
|---|---|---|
| HarmonyOS 2.x ~ 4.x(含 EMUI) | ✅ 兼容 Android APK,直接安装 | 不需要 |
| HarmonyOS NEXT(5.x 纯血鸿蒙) | ❌ 已移除 AOSP 兼容层,APK 无法安装 | 需要(本报告评估的方案) |

> 行动建议:先确认目标设备系统。若身边是华为 NEXT 设备,可在设置→关于本机查看版本号。

---

## 三、移植标的仓库现状

- **仓库**:GitCode CPF-Flutter/flutter_flutter(OpenHarmony SIG 维护),1253 Star / 357 Fork / 59 成员,社区活跃;
- **当前分支**:oh-3.35.7-release(基于 Flutter 3.35.7),可构建支持 OpenHarmony 的 Flutter Engine;
- **许可**:BSD-3-Clause(与我们应用的 GPL-3.0 应用代码无冲突,SDK 层面独立);
- **版本鸿沟**:本项目精确锁定 **Flutter 3.47.2 / Dart 3.13.2**,OHOS 分支为 **3.35.7(Dart ≈3.9)**。

---

## 四、依赖盘点(移植工作量核心)

本项目共 86 个直接依赖,lib/ 下 1310 个 Dart 文件。

### A. 纯 Dart,零成本(约 50 个)
dio、get、crypto、collection、archive、brotli、cookie_jar、dio_http2_adapter、dlna_dart、easy_debounce、encrypt、ffi、fixnum、fl_chart、flutter_svg、font_awesome_flutter、material_design_icons_flutter、html、intl、json_annotation、logger、material_color_utilities、material_ui、mime、path、pretty_qr_code、protobuf、waterfall_flow、web_socket_channel、webdav_client、characters,以及 git fork:canvas_danmaku(弹幕,CustomPainter 纯 Dart)、super_sliver_list、extended_nested_scroll_view、chat_bottom_container、catcher_2、cached_network_image_ce 等。
另:**hive_ce 为纯 Dart**(无平台目录)、**flutter_smart_dialog 为纯 Dart overlay 库**。

### B. 已内置 ohos 适配(2 个,开箱即用)
- saver_gallery 5.1.0(pubspec 已声明 ohos 平台)
- flutter_volume_controller 2.0.2(ohos/ 目录含完整 ArkTS 插件)

### C. 无 ohos 适配,需自研/替换/降级

**高危(核心功能)**:
| 包 | 用途 | OHOS 缺口 |
|---|---|---|
| media_kit 全家桶 | **视频播放(应用命脉)** | libmpv 需 OHOS NDK 交叉编译;media_kit_video 需补 ohos 平台实现(XComponent/NativeWindow + 外接纹理)。社区已有鸿蒙适配版与编译文档(见附录链接),可换 fork 引入,但版本较老 |
| flutter_inappwebview 6.1.5 | 登录/验证码(5 处调用) | 需换 OHOS Web 组件并改调用点 |
| audio_service | 后台播放/通知栏 | 需 ohos 实现(社区有 just_audio 鸿蒙化参考) |
| file_picker | 文件导入导出 | 需 ohos 实现或功能降级 |

**中危(系统能力,社区可能已有适配)**:share_plus、device_info_plus、path_provider、url_launcher、battery_plus、connectivity_plus、wakelock_plus、package_info_plus、app_links、image_picker、image_cropper、dynamic_color、screen_brightness、permission_handler、native_device_orientation、live_photo_maker——多为薄封装,可逐个引入社区 ohos fork 或补 ArkTS。

**低危(桌面专属,OHOS 可裁剪)**:win32、tray_manager、window_manager、screen_retriever、desktop_webview_window、flutter_displaymode。

**Android 专属(jni 绑定,19 个文件引用)**:画中画(PiP)、系统返回键、桌面快捷方式、字体枚举——OHOS 有对等系统能力可重写,或功能降级。DocumentsProvider(文件服务)需另找方案。

---

## 五、业务代码面(利好)

- lib/ 1310 个 Dart 文件中,仅 **69 个**触 dart:io,**45 个**有 Platform.isXxx 分支(且多为 isMobile/isDesktop 粗粒度);
- 全项目仅 **1 处 MethodChannel**(桌面全屏,OHOS 可跳过);
- 上游 PiliPlus 与本项目均无任何 ohos 痕迹(移植为从零开始,但也没有历史包袱冲突)。

---

## 六、最大隐性成本:SDK 版本鸿沟

本项目锁定 Flutter 3.47.2,且代码大量使用 Dart 3.13 新语法(点简写 `spacing: 8`、`.value` 枚举简写、switch 表达式等)。OHOS 分支 Dart ≈3.9 不支持这些语法——**降级 SDK = 全库语法回改**(数百处),或等待 OHOS 分支跟进新版(时间表未知)。

三个选项:
1. **等 OHOS 分支跟进 3.47+(推荐)**:零本项成本,但时间不可控;
2. **降级改造**:SDK 降到 3.35.7 + 全库语法回改(一周以上,且失去上游快速跟进能力);
3. **自叠 engine 适配**:为 3.47.2 自行做 OHOS engine 适配(需要 C++/gn/ninja 能力,最重)。

---

## 七、POC 路线图(确认目标设备为 NEXT 后,按此执行)

### 环境准备
1. Windows 上安装 DevEco Studio(5.x)+ OpenHarmony/HarmonyOS SDK;
2. 克隆 OHOS Flutter SDK:`git clone -b oh-3.35.7-release https://gitcode.com/CPF-Flutter/flutter_flutter.git`;
3. 配置环境变量(FLUTTER_ROOT 指向该 SDK,OHOS_SDK 指向系统内 SDK);`flutter config` / `flutter doctor` 确认 ohos 工具链;
4. 准备一台 HarmonyOS 真机或模拟器 + 签名证书。

### POC 步骤(1-2 天)
1. **空工程验证**:flutter create → `flutter build hap` → 真机安装运行,验证 SDK 链路;
2. **media_kit 验证(最关键)**:引入社区 media_kit 鸿蒙 fork(git 依赖),播一个网络视频,验证渲染/硬解/进度/倍速;
3. **hive + dio + 弹幕纯 Dart 链路**:无平台通道依赖,预期直接通过;
4. **WebView 替代验证**:OHOS Web 组件加载 B站登录页;
5. 产出 Go/No-Go 结论:若 1-2 步顺利 → 全量移植排期;若 media_kit 鸿蒙 fork 质量差 → 评估自研成本或放弃。

### 全量移植排期(POC 通过后)
- W1:SDK 降级/语法回改 + 依赖替换(plus 系插件引入社区 ohos fork);
- W2:media_kit 全量接入调试 + WebView 替换 + audio_service 替代;
- W3:Android 专属功能降级/重写 + 全功能回归测试 + 签名分发。

---

## 八、附录:参考资料

- OHOS Flutter SDK:https://gitcode.com/CPF-Flutter/flutter_flutter(分支 oh-3.35.7-release)
- libmpv OHOS 编译:https://openharmonycrossplatform.csdn.net/69393d32791c233193d42f62.html
- media_kit 鸿蒙适配指南:https://blog.csdn.net/LEO11110/article/details/156136363
- media_kit OHOS 深度适配实践:https://bbs.csdn.net/weixin_29001327/article/details/100421685
- Flutter 项目鸿蒙化全流程:https://juejin.cn/post/7527569902493990962
- 已有项目适配鸿蒙参考:https://zhuanlan.zhihu.com/p/2010092410609361767
- 插件鸿蒙化实战(just_audio):https://bbs.csdn.net/weixin_29274969/article/details/100332641

---

*本报告基于 2026-09-30 的仓库状态与社区生态评估;OHOS Flutter 生态迭代较快,若 OHOS 分支跟进 Flutter 3.47+,请重新评估第六节。*
