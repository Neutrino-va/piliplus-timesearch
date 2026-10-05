import 'dart:io' show SocketException;

import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';

/// AI 接口端点配置(OpenAI 兼容 / Anthropic)。
class AiEndpoint {
  const AiEndpoint({
    required this.apiType,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  /// openai | anthropic
  final String apiType;
  final String baseUrl;
  final String apiKey;
  final String model;

  factory AiEndpoint.fromPrefs() => AiEndpoint(
    apiType: Pref.aiApiType,
    baseUrl: Pref.aiBaseUrl,
    apiKey: Pref.aiApiKey,
    model: Pref.aiModel,
  );

  bool get configured => apiKey.isNotEmpty && model.isNotEmpty;

  /// models 列表端点(两种协议路径不同)。
  String get modelsUrl {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (apiType == 'anthropic') {
      return base.contains('/v1') ? '$base/models' : '$base/v1/models';
    }
    return base.endsWith('/v1') ? '$base/models' : '$base/v1/models';
  }

  /// 归一化后的对话端点。
  String get chatUrl {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (apiType == 'anthropic') {
      return base.contains('/v1') ? '$base/messages' : '$base/v1/messages';
    }
    return base.endsWith('/v1')
        ? '$base/chat/completions'
        : '$base/v1/chat/completions';
  }

  Map<String, Object> get headers => {
    if (apiType == 'anthropic') ...{
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    } else ...{
      'Authorization': 'Bearer $apiKey',
    },
  };
}

/// 「AI 总结」服务:用户自带 Key,调用 OpenAI 兼容或 Anthropic 接口。
///
/// 使用独立 Dio(不走全局 Request,避免B站拦截器/签名/cookie 注入);
/// 发送内容仅为该时段的统计摘要与样本标题(见各处 prompt 构建),
/// 不含完整观看历史与任何 Cookie/Token。
abstract final class AiService {
  static AiEndpoint get endpointFromPrefs => AiEndpoint.fromPrefs();

  /// 生成总结。配置缺失抛 [AiConfigException];网络/鉴权错误抛
  /// [AiServiceException](含友好中文提示)。
  static Future<String> generate({
    required String prompt,
    String system =
        '你是B站(Bilibili)数据总结助手。根据用户提供的统计数据,'
        '用轻松口语化的中文写一段不超过250字的总结,'
        '突出内容风格、兴趣偏好与亮点,可适当分点,不要编造数据。',
    AiEndpoint? endpoint,
  }) async {
    final e = endpoint ?? AiEndpoint.fromPrefs();
    if (!e.configured) {
      throw const AiConfigException();
    }
    final dio = _buildDio();
    try {
      if (e.apiType == 'anthropic') {
        final res = await dio.post(
          e.chatUrl,
          options: Options(
            headers: {...e.headers, 'content-type': 'application/json'},
          ),
          data: {
            'model': e.model,
            'max_tokens': 1024,
            'system': system,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          },
        );
        final content = res.data['content'] as List?;
        if (content != null && content.isNotEmpty) {
          return content[0]['text'] ?? '';
        }
        throw const AiServiceException('返回内容为空');
      } else {
        final res = await dio.post(
          e.chatUrl,
          options: Options(
            headers: {...e.headers, 'content-type': 'application/json'},
          ),
          data: {
            'model': e.model,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': prompt},
            ],
          },
        );
        final choices = res.data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          return choices[0]['message']['content'] ?? '';
        }
        throw const AiServiceException('返回内容为空');
      }
    } on AiConfigException {
      rethrow;
    } on AiServiceException {
      rethrow;
    } on DioException catch (err) {
      throw AiServiceException(_describe(err));
    }
  }

  /// 连接测试:对 models 端点发 GET 并测量延迟。
  /// 成功返回 (ok:true, latencyMs);失败返回 (ok:false, error:原因)。
  static Future<({bool ok, int? latencyMs, String? error})> testConnection(
    AiEndpoint e,
  ) async {
    if (e.baseUrl.isEmpty) {
      return (ok: false, latencyMs: null, error: '请先填写 Base URL');
    }
    final dio = _buildDio();
    final watch = Stopwatch()..start();
    try {
      final res = await dio.get(
        e.modelsUrl,
        options: Options(
          headers: e.headers,
          validateStatus: (_) => true, // 状态码自判,便于给出准确原因
        ),
      );
      watch.stop();
      final code = res.statusCode;
      final ok = code == 200;
      return (
        ok: ok,
        latencyMs: watch.elapsedMilliseconds,
        error: ok ? null : _statusText(code),
      );
    } on DioException catch (err) {
      watch.stop();
      return (
        ok: false,
        latencyMs: watch.elapsedMilliseconds,
        error: _describe(err, code: err.response?.statusCode),
      );
    }
  }

  /// 一键拉取模型列表(两种协议均为 GET {base}/models,data[].id)。
  static Future<List<String>> fetchModels(AiEndpoint e) async {
    if (e.baseUrl.isEmpty) {
      throw const AiServiceException('请先填写 Base URL');
    }
    final dio = _buildDio();
    try {
      final res = await dio.get(
        e.modelsUrl,
        options: Options(
          headers: e.headers,
          validateStatus: (_) => true,
        ),
      );
      final code = res.statusCode;
      if (code != 200) {
        throw AiServiceException(_statusText(code));
      }
      final data = res.data['data'] as List?;
      if (data == null) throw const AiServiceException('响应中没有模型列表');
      final ids =
          data
              .map((item) => item is Map ? item['id']?.toString() : null)
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort();
      if (ids.isEmpty) throw const AiServiceException('该接口未返回任何模型');
      return ids;
    } on AiServiceException {
      rethrow;
    } on DioException catch (err) {
      throw AiServiceException(_describe(err));
    }
  }

  static Dio _buildDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
    ),
  );

  static String _statusText(int? code) => switch (code) {
    401 || 403 => '鉴权失败($code),请检查 API Key 与 Base URL',
    404 => '接口不存在(404),请检查 Base URL 与接口类型是否匹配',
    429 => '请求过于频繁(429),请稍后重试',
    null => '请求失败',
    _ => '请求失败(code $code)',
  };

  static String _describe(DioException err, {int? code}) {
    if (err.type == DioExceptionType.connectionTimeout) {
      return '连接超时，请检查 Base URL 与网络';
    }
    if (err.type == DioExceptionType.receiveTimeout) {
      return '响应超时，请稍后重试';
    }
    final error = err.error;
    if (error is SocketException ||
        (error != null && error.toString().contains('Failed host lookup'))) {
      return '无法连接服务器，请检查网络与 Base URL';
    }
    return _statusText(code ?? err.response?.statusCode);
  }
}

class AiConfigException implements Exception {
  const AiConfigException();
}

class AiServiceException implements Exception {
  const AiServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}
