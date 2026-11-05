import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import 'company_models.dart';

/// The company's own profile. Every call needs the full `settings.*` key.
class CompanyRepository {
  CompanyRepository(this._api);
  final ApiClient _api;

  /// `GET /companies/me`.
  Future<CompanyProfile> get() async {
    final profile = CompanyProfile.tryParse(await _api.get('companies/me'));
    if (profile == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected company response.',
      );
    }
    return profile;
  }

  /// `PATCH /companies/me`. Sets only the fields it is given, so sending it again
  /// is harmless. Answers with the whole profile as it now is.
  Future<CompanyProfile> update(CompanyChange change) async {
    final profile = CompanyProfile.tryParse(
      await _api.patch('companies/me', body: change.toBody()),
    );
    if (profile == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The change may have been saved.',
      );
    }
    return profile;
  }

  /// `POST /companies/me/logo`, multipart field `logo` (an image of at most
  /// 2 MB). It replaces the logo, so sending it again is harmless. Answers with
  /// the new logo's address.
  Future<String> uploadLogo({
    required String path,
    required String fileName,
    required String contentType,
  }) async {
    final body = await _api.postMultipart(
      'companies/me/logo',
      () => FormData.fromMap({
        'logo': MultipartFile.fromFileSync(
          path,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
      }),
    );
    final url = body is Map ? body['logoUrl']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The logo may have been changed.',
      );
    }
    return url;
  }
}
