import 'package:flutter/foundation.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 登录状态与资料缓存；token 只保存在本机设置库。
class AccountService extends ChangeNotifier {
  AccountService._();

  static final AccountService _instance = AccountService._();

  factory AccountService() => _instance;

  final AccountApi _api = AccountApi.instance;

  String _token = '';
  AccountProfile? _profile;
  bool _loaded = false;

  bool get loggedIn => _token.isNotEmpty && _profile != null;
  String get token => _token;
  AccountProfile? get profile => _profile;
  String get nickname => _profile?.nickname ?? '';
  String get email => _profile?.email ?? '';
  String get avatarUrl => _profile?.avatarUrl ?? '';

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      _token = GStorage.getSetting(SettingsKeys.accountToken);
      final id = GStorage.getSetting(SettingsKeys.accountUserId);
      final email = GStorage.getSetting(SettingsKeys.accountEmail);
      if (_token.isNotEmpty && id > 0 && email.isNotEmpty) {
        _profile = AccountProfile(
          id: id,
          email: email,
          nickname: GStorage.getSetting(SettingsKeys.accountNickname),
          avatarUrl: GStorage.getSetting(SettingsKeys.accountAvatarUrl),
          emailVerified: true,
        );
      }
    } catch (_) {
      // 存储尚未初始化时保持未登录状态。
    }
  }

  Future<void> _persist(AccountAuthResult result) async {
    _token = result.token;
    _profile = result.profile;
    _loaded = true;
    await GStorage.putSetting(SettingsKeys.accountToken, result.token);
    await GStorage.putSetting(SettingsKeys.accountUserId, result.profile.id);
    await GStorage.putSetting(SettingsKeys.accountEmail, result.profile.email);
    await GStorage.putSetting(
      SettingsKeys.accountNickname,
      result.profile.nickname,
    );
    await GStorage.putSetting(
      SettingsKeys.accountAvatarUrl,
      result.profile.avatarUrl,
    );
    notifyListeners();
  }

  Future<void> _persistProfile(AccountProfile profile) async {
    _profile = profile;
    await GStorage.putSetting(SettingsKeys.accountNickname, profile.nickname);
    await GStorage.putSetting(SettingsKeys.accountAvatarUrl, profile.avatarUrl);
    notifyListeners();
  }

  Future<void> sendCode(String email, {String purpose = 'register'}) =>
      _api.sendCode(email.trim(), purpose: purpose);

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    await _api.resetPassword(
      email: email.trim(),
      code: code.trim(),
      password: password,
    );
  }

  Future<void> register({
    required String email,
    required String code,
    required String password,
    required String nickname,
  }) async {
    final result = await _api.register(
      email: email.trim(),
      code: code.trim(),
      password: password,
      nickname: nickname.trim(),
    );
    await _persist(result);
  }

  Future<void> login({required String email, required String password}) async {
    final result = await _api.login(email: email.trim(), password: password);
    await _persist(result);
  }

  Future<void> refresh() async {
    ensureLoaded();
    if (_token.isEmpty) return;
    try {
      final profile = await _api.me(_token);
      await _persistProfile(profile);
    } on AccountException catch (e) {
      // 令牌失效时清除本地登录态，避免每次启动都重复失败。
      if (e.statusCode == 401) {
        await logout();
      }
      rethrow;
    }
  }

  Future<void> updateNickname(String nickname) async {
    final profile = await _api.updateNickname(_token, nickname.trim());
    await _persistProfile(profile);
  }

  Future<void> uploadAvatar(String filePath) async {
    final profile = await _api.uploadAvatar(_token, filePath);
    await _persistProfile(profile);
  }

  Future<void> logout() async {
    final token = _token;
    _token = '';
    _profile = null;
    await GStorage.putSetting(SettingsKeys.accountToken, '');
    await GStorage.putSetting(SettingsKeys.accountUserId, 0);
    await GStorage.putSetting(SettingsKeys.accountEmail, '');
    await GStorage.putSetting(SettingsKeys.accountNickname, '');
    await GStorage.putSetting(SettingsKeys.accountAvatarUrl, '');
    notifyListeners();
    if (token.isNotEmpty) {
      await _api.logout(token);
    }
  }
}
