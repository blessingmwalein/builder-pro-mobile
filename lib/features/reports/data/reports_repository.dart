import '../../../core/network/api_client.dart';
import 'report_models.dart';

/// `/reporting/*`: read-only reports. Only the two that carry no money or pay
/// (delays, productivity) are used; profitability, labour and budget reports
/// stay on the web app.
class ReportsRepository {
  ReportsRepository(this._api);

  final ApiClient _api;

  /// `GET /reporting/delays` (needs `reports.view`).
  Future<DelayReport> delays() async =>
      DelayReport.parse(await _api.get('reporting/delays'));

  /// `GET /reporting/productivity` (needs `reports.view`).
  Future<ProductivityReport> productivity() async =>
      ProductivityReport.parse(await _api.get('reporting/productivity'));
}
