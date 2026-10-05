// 注意:全应用统一使用 material_ui 分叉包(MaterialLocalizations 等类型
// 与原生 flutter/material 不互通);这里若导入原生库,showDialog 会因
// 查不到 MaterialLocalizations 而在 release 下空指针,表现为点击无反应。
import 'package:material_ui/material_ui.dart';
import 'package:dio/dio.dart';
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
  final _cancelToken = CancelToken();
  final _scrollController = ScrollController();

  String _text = '';
  String _reasoning = '';
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    if (!_done) _cancelToken.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _text = '';
      _reasoning = '';
      _error = null;
      _done = false;
    });
    try {
      await aiGenerateStream(
        prompt: widget.prompt,
        cancelToken: _cancelToken,
        onDelta: (full) {
          if (mounted) {
            setState(() => _text = full);
            _autoScroll();
          }
        },
        onReasoning: (piece) {
          if (mounted) {
            setState(() => _reasoning += piece);
            _autoScroll();
          }
        },
      );
      if (mounted) setState(() => _done = true);
    } on AiConfigException {
      if (mounted) {
        setState(() {
          _error = '尚未配置 AI 接口，请到 设置→其它设置→AI 总结设置 填写';
          _done = true;
        });
      }
    } on AiServiceException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _done = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '请求失败：$e';
          _done = true;
        });
      }
    }
    _autoScroll();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('AI 总结 · ${widget.title}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              if (_reasoning.isNotEmpty)
                Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: _text.isEmpty,
                    iconColor: theme.colorScheme.outline,
                    collapsedIconColor: theme.colorScheme.outline,
                    title: Text(
                      '思考过程',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          _reasoning,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_text.isNotEmpty)
                SelectableText(
                  _text,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.error,
                  ),
                )
              else if (_done)
                Text(
                  '未收到生成内容',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.outline,
                  ),
                )
              else
                Row(
                  spacing: 10,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    Text(
                      '正在连接模型…',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              if (_done && _error == null && _text.isNotEmpty)
                Text(
                  '该总结由 AI 生成，可能存在偏差；统计数据已发送至你配置的接口。',
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
        if (!_done && _error == null)
          TextButton(
            onPressed: () {
              _cancelToken.cancel();
              Navigator.of(context).pop();
            },
            child: const Text('停止生成'),
          )
        else
          TextButton(onPressed: _start, child: const Text('重新生成')),
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
