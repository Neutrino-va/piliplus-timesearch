import 'package:flutter/material.dart';
import 'package:PiliPlus/http/ai.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// AI 总结对话框:打开即请求,加载态转圈,完成后展示可复制的总结文本,
/// 支持「重新生成」。未配置 AI 接口时提示前往设置。
Future<void> showAiSummaryDialog(
  BuildContext context, {
  required String title,
  required String prompt,
}) async {
  if (!AiEndpoint.fromPrefs().configured) {
    SmartDialog.showToast('请先在 设置→其它设置→AI 总结设置 中配置接口');
    return;
  }
  await showDialog(
    context: context,
    builder: (_) => _AiSummaryDialog(title: title, prompt: prompt),
  );
}

class _AiSummaryDialog extends StatefulWidget {
  const _AiSummaryDialog({required this.title, required this.prompt});

  final String title;
  final String prompt;

  @override
  State<_AiSummaryDialog> createState() => _AiSummaryDialogState();
}

class _AiSummaryDialogState extends State<_AiSummaryDialog> {
  String? _result;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final text = await AiService.generate(prompt: widget.prompt);
      if (mounted) setState(() => _result = text);
    } on AiConfigException {
      if (mounted) {
        setState(
          () => _error = '尚未配置 AI 接口，请到 设置→其它设置→AI 总结设置 填写',
        );
      }
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('AI 总结 · ${widget.title}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else
                SelectableText(
                  _result ?? '',
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              Text(
                '该总结由 AI 生成，可能存在偏差；统计数据将发送至你配置的接口。',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_loading && _result != null)
          TextButton(onPressed: _generate, child: const Text('重新生成')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// AI 总结入口按钮(统一样式,用于各回顾模式标题行)。
class AiSummaryButton extends StatelessWidget {
  const AiSummaryButton({
    super.key,
    required this.title,
    required this.promptBuilder,
  });

  final String title;
  final String Function() promptBuilder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showAiSummaryDialog(
        context,
        title: title,
        prompt: promptBuilder(),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 13,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              'AI总结',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
