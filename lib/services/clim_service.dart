import 'package:dio/dio.dart';
import '../services/tor_service.dart';

class ClimService {
  static Dio _buildDio(String apiKey) {
    final options = BaseOptions(
      baseUrl: 'https://api.anthropic.com',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    );
    final dio = Dio(options);
    if (TorService.isRunning) {
      // Route through Orbot SOCKS5
      // Dio doesn't support SOCKS5 natively; use HttpClient adapter
      // For now we rely on system-level proxy set by Orbot
    }
    return dio;
  }

  static Future<String> sendMessage({
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    int maxTokens = 2048,
  }) async {
    final dio = _buildDio(apiKey);
    Response response;
    try {
      response = await dio.post(
        '/v1/messages',
        data: {
          'model': model,
          'messages': messages,
          'max_tokens': maxTokens,
        },
        options: Options(validateStatus: (_) => true),
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? e.type.name}');
    }

    final status = response.statusCode ?? 0;
    final data = response.data;

    if (status < 200 || status >= 300) {
      String message = 'HTTP $status';
      if (data is Map) {
        final err = data['error'];
        if (err is Map && err['message'] is String) {
          message = '${err['type'] ?? 'error'}: ${err['message']}';
        } else if (data['message'] is String) {
          message = data['message'] as String;
        }
      }
      throw Exception(message);
    }

    if (data is! Map) throw Exception('Unexpected response shape');
    final content = data['content'];
    if (content is! List || content.isEmpty) {
      throw Exception('Empty response from API');
    }
    final first = content.first;
    if (first is! Map || first['text'] is! String) {
      throw Exception('Unexpected content block shape');
    }
    return first['text'] as String;
  }

  static Future<String> explainCode({
    required String apiKey,
    required String model,
    required String code,
    required String language,
  }) async {
    return sendMessage(
      apiKey: apiKey,
      model: model,
      messages: [
        {
          'role': 'user',
          'content':
              'Explain this $language code concisely:\n\n```$language\n$code\n```',
        }
      ],
    );
  }

  static Future<String> completeCode({
    required String apiKey,
    required String model,
    required String prefix,
    required String language,
  }) async {
    return sendMessage(
      apiKey: apiKey,
      model: model,
      messages: [
        {
          'role': 'user',
          'content':
              'Complete this $language code. Return ONLY the completion, no explanation:\n\n```$language\n$prefix',
        }
      ],
      maxTokens: 512,
    );
  }
}
