import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';

/// 「AI 总结」服务:用户自带 Key,调用 OpenAI 兼容或 Anthropic 接口。
///
/// 使用独立 Dio(不走全局 Request,避免B站拦截器/签名/cookie 注入);
/// 发送内容仅为该时段的统计摘要与样本标题(见各处 prompt 构建),
/// 不含完整观看历史与任何 Cookie/Token。
abstract final class AiService {
  static bool get configured => Pref.aiApiKey.isNotEmpty && Pref.aiModel.isNotEmpty;

  static String get _base {
    final base = Pref.aiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return base;
  }

  /// 生成总结。配置缺失抛 [AiConfigException];网络/鉴权错误抛
  /// [AiServiceException](含友好中文提示)。
  static Future<String> generate({
    required String prompt,
    String system =
        '你是B站(Bilibili)数据总结助手。根据用户提供的统计数据,'
        '用轻松口语化的中文写一段不超过250字的总结,'
        '突出内容风格、兴趣偏好与亮点,可适当分点,不要编造数据。',
  }) async {
    if (Pref.aiApiKey.isEmpty || Pref.aiModel.isEmpty) {
      throw const AiConfigException();
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    final apiType = Pref.aiApiType;
    try {
      if (apiType == 'anthropic') {
        final base = _base.contains('/v1')
            ? _base
            : '$_base/v1';
        final res = await dio.post(
          '$base/messages',
          options: Options(
            headers: {
              'x-api-key': Pref.aiApiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
          ),
          data: {
            'model': Pref.aiModel,
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
        // OpenAI 兼容
        final base = _base.endsWith('/v1') ? _base : '$_base/v1';
        final res = await dio.post(
          '$base/chat/completions',
          options: Options(
            headers: {
              'Authorization': 'Bearer ${Pref.aiApiKey}',
              'content-type': 'application/json',
            },
          ),
          data: {
            'model': Pref.aiModel,
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
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final msg = e.response?.data is Map
          ? (e.response!.data['error']?['message'] ??
              e.response!.data['message'])
          : null;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const AiServiceException('请求超时,请稍后重试');
      }
      if (code == 401 || code == 403) {
        throw AiServiceException('鉴权失败($code),请检查 API Key');
      }
      if (code == 429) {
        throw const AiServiceException('请求过于频繁,请稍后重试');
      }
      throw AiServiceException(msg?.toString() ?? '请求失败(code $code)');
    }
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
