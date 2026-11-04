import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';

class AccountException implements Exception {
  const AccountException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.email,
    required this.nickname,
    required this.avatarUrl,
    required this.emailVerified,
  });

  final int id;
  final String email;
  final String nickname;
  final String avatarUrl;
  final bool emailVerified;

  factory AccountProfile.fromJson(Map<String, dynamic> json, String avatarUrl) {
    return AccountProfile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: (json['email'] ?? '').toString(),
      nickname: (json['nickname'] ?? '').toString(),
      avatarUrl: avatarUrl,
      emailVerified: json['emailVerified'] == true,
    );
  }
}

class AccountAuthResult {
  const AccountAuthResult({required this.token, required this.profile});

  final String token;
  final AccountProfile profile;
}

class AccountBlob {
  const AccountBlob({required this.payload, required this.updatedAt});

  final String payload;
  final int updatedAt;
}

class AccountBlobInfo {
  const AccountBlobInfo({required this.kind, required this.size});

  final String kind;
  final int size;
}

class AccountApi {
  AccountApi._();

  static final AccountApi instance = AccountApi._();

  String get baseUrl {
    var value = GStorage.getSetting(SettingsKeys.accountApiBase).trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Dio get _dio => DioFactory.apiDio;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? data,
    String? token,
  }) async {
    final uri = '$baseUrl$path';
    try {
      final response = await _dio.request<dynamic>(
        uri,
        data: data,
        options: Options(
          method: method,
          headers: {
            if (token != null && token.isNotEmpty)
              'authorization': 'Bearer $token',
          },
        ),
      );
      final body = response.data;
      if (body is Map<String, dynamic>) return body;
      if (body is Map) return Map<String, dynamic>.from(body);
      throw const AccountException('服务器返回了无法识别的数据');
    } on DioException catch (e) {
      final body = e.response?.data;
      String? message;
      if (body is Map && body['error'] != null) {
        message = body['error'].toString();
      }
      throw AccountException(
        message ?? _networkMessage(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  String _networkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '连接服务器超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接账号服务器';
      default:
        final code = e.response?.statusCode;
        return code == null ? '网络异常，请稍后重试' : '服务器返回 $code';
    }
  }

  AccountAuthResult _authResult(Map<String, dynamic> body) {
    final token = (body['token'] ?? '').toString();
    final user = body['user'];
    if (token.isEmpty || user is! Map) {
      throw const AccountException('服务器返回的登录信息不完整');
    }
    final profile = AccountProfile.fromJson(
      Map<String, dynamic>.from(user),
      (body['avatarUrl'] ?? '').toString(),
    );
    return AccountAuthResult(token: token, profile: profile);
  }

  Future<void> sendCode(String email, {String purpose = 'register'}) async {
    await _request(
      'POST',
      '/v1/auth/send-code',
      data: {'email': email, 'purpose': purpose},
    );
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    await _request(
      'POST',
      '/v1/auth/reset',
      data: {'email': email, 'code': code, 'password': password},
    );
  }

  Future<AccountAuthResult> register({
    required String email,
    required String code,
    required String password,
    required String nickname,
  }) async {
    final body = await _request(
      'POST',
      '/v1/auth/register',
      data: {
        'email': email,
        'code': code,
        'password': password,
        'nickname': nickname,
      },
    );
    return _authResult(body);
  }

  Future<AccountAuthResult> login({
    required String email,
    required String password,
  }) async {
    final body = await _request(
      'POST',
      '/v1/auth/login',
      data: {'email': email, 'password': password},
    );
    return _authResult(body);
  }

  Future<void> logout(String token) async {
    try {
      await _request('POST', '/v1/auth/logout', token: token);
    } on AccountException {
      // 本地退出不依赖服务端是否可达。
    }
  }

  Future<AccountProfile> me(String token) async {
    final body = await _request('GET', '/v1/me', token: token);
    final user = body['user'];
    if (user is! Map) throw const AccountException('读取账号资料失败');
    return AccountProfile.fromJson(
      Map<String, dynamic>.from(user),
      (body['avatarUrl'] ?? '').toString(),
    );
  }

  Future<AccountProfile> updateNickname(String token, String nickname) async {
    final body = await _request(
      'PATCH',
      '/v1/me',
      token: token,
      data: {'nickname': nickname},
    );
    final user = body['user'];
    if (user is! Map) throw const AccountException('修改昵称失败');
    return AccountProfile.fromJson(
      Map<String, dynamic>.from(user),
      (body['avatarUrl'] ?? '').toString(),
    );
  }

  Future<AccountProfile> uploadAvatar(String token, String filePath) async {
    final form = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(filePath),
    });
    final body = await _request(
      'POST',
      '/v1/me/avatar',
      token: token,
      data: form,
    );
    final user = body['user'];
    if (user is! Map) throw const AccountException('上传头像失败');
    return AccountProfile.fromJson(
      Map<String, dynamic>.from(user),
      (body['avatarUrl'] ?? '').toString(),
    );
  }

  Future<bool> health() async {
    try {
      final body = await _request('GET', '/v1/health');
      return body['ok'] == true && body['db'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<AccountBlobInfo>> listBlobInfos(String token) async {
    final body = await _request('GET', '/v1/sync', token: token);
    final items = body['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map && item['kind'] != null)
          AccountBlobInfo(
            kind: item['kind'].toString(),
            size: (item['size'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  Future<void> deleteBlob(String token, String kind) async {
    await _request('DELETE', '/v1/sync/$kind', token: token);
  }

  Future<List<String>> listBlobs(String token) async {
    final body = await _request('GET', '/v1/sync', token: token);
    final items = body['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map && item['kind'] != null) item['kind'].toString(),
    ];
  }

  Future<AccountBlob?> getBlob(String token, String kind) async {
    try {
      final body = await _request('GET', '/v1/sync/$kind', token: token);
      final payload = (body['payload'] ?? '').toString();
      if (payload.isEmpty) return null;
      return AccountBlob(
        payload: payload,
        updatedAt: (body['updatedAt'] as num?)?.toInt() ?? 0,
      );
    } on AccountException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> putBlob(
    String token,
    String kind,
    String payload, {
    required int updatedAt,
  }) async {
    await _request(
      'PUT',
      '/v1/sync/$kind',
      token: token,
      data: {'payload': payload, 'updatedAt': updatedAt},
    );
  }

  Future<AccountCommentPage> listComments({
    required String targetType,
    required int targetId,
    int offset = 0,
    int limit = 20,
    String? token,
  }) async {
    final body = await _request(
      'GET',
      '/v1/comments?targetType=$targetType&targetId=$targetId'
      '&offset=$offset&limit=$limit',
      token: token,
    );
    final items = body['items'];
    return AccountCommentPage(
      total: (body['total'] as num?)?.toInt() ?? 0,
      items: [
        if (items is List)
          for (final item in items)
            if (item is Map<String, dynamic>) AccountComment.fromJson(item),
      ],
    );
  }

  Future<AccountComment> createComment({
    required String token,
    required String targetType,
    required int targetId,
    required String content,
    bool spoiler = false,
  }) async {
    final body = await _request(
      'POST',
      '/v1/comments',
      token: token,
      data: {
        'targetType': targetType,
        'targetId': targetId,
        'content': content,
        'spoiler': spoiler,
      },
    );
    final comment = body['comment'];
    if (comment is! Map<String, dynamic>) {
      throw const AccountException('服务器返回的吐槽数据不完整');
    }
    return AccountComment.fromJson(comment);
  }

  Future<void> deleteComment({
    required String token,
    required int id,
  }) async {
    await _request('DELETE', '/v1/comments/$id', token: token);
  }

  /// 单集评论：按 (bangumiId, episode) 读取全部条目。
  Future<AccountCommentPage> listEpisodeComments({
    required int bangumiId,
    required int episode,
    String? token,
  }) async {
    return listComments(
      targetType: 'episode',
      targetId: bangumiId * 10000 + episode,
      token: token,
    );
  }

  Future<AccountComment> createEpisodeComment({
    required String token,
    required int bangumiId,
    required int episode,
    required String content,
    bool spoiler = false,
  }) async {
    return createComment(
      token: token,
      targetType: 'episode',
      targetId: bangumiId * 10000 + episode,
      content: content,
      spoiler: spoiler,
    );
  }
}

class AccountCommentPage {
  const AccountCommentPage({required this.total, required this.items});

  final int total;
  final List<AccountComment> items;
}

class AccountComment {
  const AccountComment({
    required this.id,
    required this.content,
    required this.spoiler,
    required this.createdAt,
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.mine,
  });

  final int id;
  final String content;
  final bool spoiler;
  final int createdAt;
  final int userId;
  final String nickname;
  final String avatarUrl;
  final bool mine;

  factory AccountComment.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final map = user is Map<String, dynamic> ? user : const <String, dynamic>{};
    return AccountComment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      content: (json['content'] ?? '').toString(),
      spoiler: json['spoiler'] == true,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      userId: (map['id'] as num?)?.toInt() ?? 0,
      nickname: (map['nickname'] ?? '').toString(),
      avatarUrl: (map['avatarUrl'] ?? '').toString(),
      mine: json['mine'] == true,
    );
  }
}
