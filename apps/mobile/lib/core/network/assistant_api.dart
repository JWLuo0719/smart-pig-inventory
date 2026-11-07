import 'package:dio/dio.dart';
import 'api_client.dart';

class AssistantApi {
  AssistantApi({required String baseUrl, Dio? dio})
      : _dio = dio ??
            createApiDio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 65),
            ));

  final Dio _dio;

  Options _options(String token) => Options(headers: {
        'Authorization': 'Bearer $token',
      });

  Future<bool> enabled(String token, CancelToken cancel) async {
    final response = await _dio.get('/api/v1/assistant/status',
        options: _options(token), cancelToken: cancel);
    return (response.data as Map<String, dynamic>)['enabled'] == true;
  }

  Future<AssistantReply> ask({
    required String token,
    required String message,
    required DateTime date,
    required CancelToken cancel,
    String? penId,
    String? sessionId,
  }) async {
    final response = await _dio.post('/api/v1/assistant/chat',
        options: _options(token),
        cancelToken: cancel,
        data: {
          'message': message,
          'businessDate': date.toIso8601String().substring(0, 10),
          if (penId != null) 'penId': penId,
          if (sessionId != null) 'sessionId': sessionId,
        });
    return AssistantReply.fromJson(response.data as Map<String, dynamic>);
  }
}

class AssistantReply {
  const AssistantReply(
      {required this.status,
      required this.answer,
      required this.facts,
      required this.evidence});
  final String status;
  final String? answer;
  final List<Map<String, dynamic>> facts;
  final List<Map<String, dynamic>> evidence;

  factory AssistantReply.fromJson(Map<String, dynamic> body) {
    final status = body['status'];
    if (!const [
          'ok',
          'insufficient_evidence',
          'answer_rejected',
          'model_unavailable',
          'limit_reached'
        ].contains(status) ||
        (body['answer'] != null && body['answer'] is! String) ||
        body['facts'] is! List ||
        body['evidence'] is! List ||
        (body['facts'] as List).length > 6 ||
        (body['evidence'] as List).length > 50) {
      throw const FormatException('Invalid assistant reply');
    }
    for (final value in body['facts'] as List) {
      if (value is! Map<String, dynamic> ||
          value['tool'] is! String ||
          value['status'] is! String ||
          (value['data'] != null && value['data'] is! Map<String, dynamic>)) {
        throw const FormatException('Invalid assistant fact');
      }
      final data = value['data'];
      if (value['status'] != 'ok' || data == null) continue;
      if (value['tool'] == 'get_pen_history' &&
          (data['points'] is! List ||
              (data['points'] as List).length > 90 ||
              (data['points'] as List).any((point) =>
                  point is! Map<String, dynamic> ||
                  point['date'] is! String ||
                  !_validCount(point['confirmedCount'])))) {
        throw const FormatException('Invalid assistant history');
      }
      final keys = switch (value['tool']) {
        'inspect_session' => ['candidateCount', 'confirmedCount'],
        'get_day_overview' => [
            'confirmedHeads',
            'confirmedPenCount',
            'scopePenCount'
          ],
        _ => <String>[],
      };
      if (keys.any((key) => !_validCount(data[key]))) {
        throw const FormatException('Invalid assistant counts');
      }
    }
    if ((body['evidence'] as List)
        .any((value) => value is! Map<String, dynamic>)) {
      throw const FormatException('Invalid assistant evidence');
    }
    return AssistantReply(
      status: status as String,
      answer: status == 'ok' ? body['answer'] as String? : null,
      facts: (body['facts'] as List).cast<Map<String, dynamic>>(),
      evidence: (body['evidence'] as List).cast<Map<String, dynamic>>(),
    );
  }

  static bool _validCount(Object? value) =>
      value == null || value is int && value >= 0;
}
