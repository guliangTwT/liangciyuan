import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/sync/webdav.dart';

void main() {
  group('WebDav.describeError', () {
    test('explains 503 as rate limiting or maintenance', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/kazumiSync'),
        response: Response(
          requestOptions: RequestOptions(path: '/kazumiSync'),
          statusCode: 503,
        ),
      );

      final message = WebDav.describeError(error);
      expect(message, contains('503'));
      expect(message, contains('稍后重试'));
    });

    test('explains 429 as rate limiting', () {
      final message = WebDav.describeError(
        Exception('newResponseError: status code: 429'),
      );
      expect(message, contains('429'));
      expect(message, contains('限流'));
    });

    test('keeps 401 actionable', () {
      final message = WebDav.describeError(
        Exception('newResponseError: status code: 401'),
      );
      expect(message, contains('账号或密码错误'));
    });

    test('falls back to the original text', () {
      expect(WebDav.describeError(Exception('boom')), contains('boom'));
    });
  });
}
