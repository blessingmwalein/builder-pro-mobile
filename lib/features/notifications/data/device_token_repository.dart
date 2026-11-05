import '../../../core/network/api_client.dart';

/// Tells the server which phone to send this person's alerts to.
/// `POST /notifications/devices` and `POST /notifications/devices/unregister`
/// (any signed-in user; they only ever touch their own devices). Both are safe
/// to repeat: registering the same token again just refreshes it.
class DeviceTokenRepository {
  DeviceTokenRepository(this._api);

  final ApiClient _api;

  Future<void> register(String token, {required String platform}) async {
    await _api.post(
      'notifications/devices',
      body: {'token': token, 'platform': platform},
    );
  }

  Future<void> unregister(String token) async {
    await _api.post('notifications/devices/unregister', body: {'token': token});
  }
}
