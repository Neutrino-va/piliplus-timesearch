// 「AI 设置助手」:基于用户自配 AI 接口的对话式设置向导。
// 模型在回答中内嵌 <<SET:key=value>> 指令,由 setting_agent.dart
// 的注册表校验并落盘;思考过程不展示,仅呈现最终回答与执行结果。
import 'package:material_ui/material_ui.dart';

import 'package:PiliPlus/http/ai.dart';
import 'package:PiliPlus/pages/setting/models/ai_config_dialog.dart';
import 'package:PiliPlus/services/setting_agent.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  /// 会话消息(仅内存,退出页面即清空)
  final List<_ChatMsg> _messages = <_ChatMsg>[];
  CancelToken? _cancelToken;
  bool _busy = false;

  @override
  void dispose() {
    _cancelToken?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// 把最近几轮对话折叠进 prompt,形成轻量多轮上下文。
  String _buildPrompt(String text) {
    final msgs = _messages.sublist(0, _messages.length - 1);
    final recent = msgs.length > 10 ? msgs.sublist(msgs.length - 10) : msgs;
    final lines = recent
        .where((m) => m.text.isNotEmpty)
        .map((m) => '${m.isUser ? '用户' : '助手'}: ${m.text}')
        .join('\n');
    return lines.isEmpty ? text : '对话记录(旧→新):\n$lines\n\n用户新消息:$text';
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _busy) return;
    if (!AiEndpoint.fromPrefs().configured) {
      SmartDialog.showToast('请先在 设置→其它设置→AI 总结设置 中配置接口');
      return;
    }
    _textController.clear();
    _focusNode.unfocus();
    setState(() {
      _messages
        ..add(_ChatMsg.user(text))
        ..add(_ChatMsg.assistant(''));
      _busy = true;
    });
    _autoScroll();

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    String full = '';
    String? error;
    try {
      await aiGenerateStream(
        prompt: _buildPrompt(text),
        system: buildAgentSystemPrompt(),
        cancelToken: cancelToken,
        onDelta: (fullText) {
          full = fullText;
          if (mounted) {
            setState(
              () => _messages.last.text = stripSettingDirectives(fullText),
            );
            _autoScroll();
          }
        },
      );
    } on AiConfigException {
      error = '尚未配置 AI 接口,请到 设置→其它设置→AI 总结设置 填写';
    } on AiServiceException catch (e) {
      error = e.message;
    } catch (e) {
      if (!cancelToken.isCancelled) error = '请求失败:$e';
    }
    if (!mounted) return;

    // 流结束:执行回答中内嵌的设置指令
    final actions = <String>[];
    if (error == null) {
      for (final (key, value) in extractSettingDirectives(full)) {
        actions.add(await applySettingDirective(key, value));
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _cancelToken = null;
      if (error != null) {
        _messages.last.text = _messages.last.text.isEmpty
            ? error
            : '${_messages.last.text}\n\n⚠ $error';
      } else if (_messages.last.text.isEmpty && actions.isEmpty) {
        _messages.last.text = '(模型没有返回内容,试试换个问法)';
      }
      if (actions.isNotEmpty) _messages.add(_ChatMsg.actions(actions));
    });
    _autoScroll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = AiEndpoint.fromPrefs().configured;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 设置助手'),
        actions: [
          IconButton(
            tooltip: '清空对话',
            onPressed: _busy
                ? null
                : () => setState(() {
                  _messages.clear();
                }),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (!configured) _buildConfigBanner(theme),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyHint(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _bubble(_messages[i], theme),
                  ),
          ),
          _buildInputBar(theme, configured),
        ],
      ),
    );
  }

  Widget _buildConfigBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '先在「AI 总结设置」填好 Base URL / API Key / 模型,助手即可使用',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => showAiConfigDialog(context, () => setState(() {})),
            child: const Text('去配置'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHint(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final examples = [
      '把主题换成深色',
      '默认画质改成 1080P 高清',
      '弹幕字号调到 1.3',
      '视频总结入口在哪里?',
    ];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_outlined, size: 52, color: colorScheme.outline),
          const SizedBox(height: 10),
          Text(
            '你好,我是设置助手 🤖',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '问我某个设置在哪,或让我直接帮你改',
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final e in examples)
                ActionChip(
                  label: Text(e, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _textController.text = e;
                    _send();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bubble(_ChatMsg msg, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    if (msg.actions != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(top: 2, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              for (final line in msg.actions!)
                Text(
                  line,
                  style: TextStyle(
                    fontSize: 12,
                    color: line.startsWith('✓')
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: msg.isUser
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          msg.text,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: msg.isUser ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, bool configured) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                enabled: configured,
                decoration: InputDecoration(
                  hintText: configured ? '问我设置相关的问题…' : '先配置 AI 接口',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: _busy ? '停止生成' : '发送',
              onPressed: configured
                  ? (_busy ? _cancelToken?.cancel : _send)
                  : null,
              icon: Icon(_busy ? Icons.stop : Icons.send, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMsg {
  _ChatMsg.user(this.text) : isUser = true, actions = null;
  _ChatMsg.assistant(this.text) : isUser = false, actions = null;
  _ChatMsg.actions(this.actions) : isUser = false, text = '';

  final bool isUser;
  String text = '';
  final List<String>? actions;
}
