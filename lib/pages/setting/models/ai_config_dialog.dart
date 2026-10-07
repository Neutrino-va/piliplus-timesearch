// AI 总结接口配置对话框:设置页与「AI 设置助手」共用。
// 注意:必须导入 material_ui 分叉包(原因见 ai_summary.dart 顶部注释)。
import 'package:material_ui/material_ui.dart';

import 'package:PiliPlus/http/ai.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 弹出 AI 接口配置(协议/Base URL/Key/模型 + 连接测试/拉取模型列表)。
/// [onChanged] 在保存成功后回调,用于刷新调用方的设置项 subtitle。
Future<void> showAiConfigDialog(
  BuildContext context,
  VoidCallback onChanged,
) async {
  final typeController = TextEditingController(text: Pref.aiApiType);
  final baseController = TextEditingController(text: Pref.aiBaseUrl);
  final keyController = TextEditingController(text: Pref.aiApiKey);
  final modelController = TextEditingController(text: Pref.aiModel);
  // 测试连接 / 模型列表状态(随对话框内当前填写值实时更新)
  String? testResult;
  bool? testOk;
  bool testing = false;
  bool fetchingModels = false;
  List<String> modelList = const [];

  void clearProbe() {
    testResult = null;
    testOk = null;
    modelList = const [];
  }

  AiEndpoint endpointFromFields() => AiEndpoint(
    apiType: typeController.text == 'anthropic' ? 'anthropic' : 'openai',
    baseUrl: baseController.text.trim(),
    apiKey: keyController.text.trim(),
    model: modelController.text.trim(),
  );

  Future<void> doTest(void Function(void Function()) setState) async {
    setState(() {
      testing = true;
      clearProbe();
    });
    final result = await AiService.testConnection(endpointFromFields());
    setState(() {
      testing = false;
      testOk = result.ok;
      testResult = result.ok
          ? '✓ 连接成功 · 延迟 ${result.latencyMs}ms'
          : '✕ ${result.error ?? '连接失败'}';
    });
  }

  Future<void> doFetchModels(void Function(void Function()) setState) async {
    setState(() {
      fetchingModels = true;
      clearProbe();
    });
    try {
      final models = await AiService.fetchModels(endpointFromFields());
      setState(() {
        fetchingModels = false;
        modelList = models;
      });
    } on AiServiceException catch (e) {
      setState(() {
        fetchingModels = false;
        testOk = false;
        testResult = '✕ ${e.message}';
      });
    }
  }

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('AI 总结设置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('接口类型'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('OpenAI 兼容'),
                      selected: typeController.text != 'anthropic',
                      onSelected: (_) {
                        setState(() => typeController.text = 'openai');
                        clearProbe();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Anthropic'),
                      selected: typeController.text == 'anthropic',
                      onSelected: (_) {
                        setState(() => typeController.text = 'anthropic');
                        clearProbe();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: baseController,
                onChanged: (_) => clearProbe(),
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: typeController.text == 'anthropic'
                      ? 'https://api.anthropic.com'
                      : 'https://api.openai.com/v1',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: keyController,
                obscureText: true,
                onChanged: (_) => clearProbe(),
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: testing || fetchingModels
                          ? null
                          : () => doTest(setState),
                      icon: testing
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.network_check, size: 16),
                      label: const Text('测试连接'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: testing || fetchingModels
                          ? null
                          : () => doFetchModels(setState),
                      icon: fetchingModels
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.list_alt, size: 16),
                      label: const Text('拉取模型'),
                    ),
                  ),
                ],
              ),
              if (testResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    testResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: testOk == true
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: '模型名',
                  hintText: '如 deepseek-chat / glm-4-flash / claude-sonnet-4',
                  border: OutlineInputBorder(),
                ),
              ),
              if (modelList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '从接口拉取到 ${modelList.length} 个模型，点击选择：',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final model in modelList.take(60))
                          GestureDetector(
                            onTap: () => modelController.text = model,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: modelController.text == model
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withValues(
                                        alpha: 0.06,
                                      ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                model,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: modelController.text == model
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '仅保存在本机，用于「年份回顾」AI 总结与「AI 设置助手」；'
                '使用时会把对应请求发送至此接口。',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          TextButton(
            onPressed: () {
              GStorage.setting
                ..put(SettingBoxKey.aiApiType, typeController.text)
                ..put(SettingBoxKey.aiBaseUrl, baseController.text.trim())
                ..put(SettingBoxKey.aiApiKey, keyController.text.trim())
                ..put(SettingBoxKey.aiModel, modelController.text.trim());
              Get.back();
              SmartDialog.showToast('已保存');
              onChanged();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
