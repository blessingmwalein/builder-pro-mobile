import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../data/company_models.dart';
import '../data/company_repository.dart';

final companyRepositoryProvider = Provider<CompanyRepository>(
  (ref) => CompanyRepository(ref.watch(apiClientProvider)),
);

/// The whole company profile. Needs `settings.*`; a role without it gets the
/// server's "not allowed" and the screen shows only what the sign-in already
/// carries.
final companyProfileProvider = FutureProvider.autoDispose<CompanyProfile>((
  ref,
) {
  ref.watch(currentUserIdProvider);
  return ref.watch(companyRepositoryProvider).get();
});

/// Changing the company's profile, details and settings, and its logo.
///
/// Both only set values, so after an uncertain failure each is sent once more; a
/// second failure is reported. The signed-in company (its name and logo shown
/// around the app) is then reloaded.
class CompanyActions {
  CompanyActions(this._ref);
  final Ref _ref;

  CompanyRepository get _repo => _ref.read(companyRepositoryProvider);

  Future<T> _twice<T>(Future<T> Function() send) async {
    try {
      return await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      return send();
    }
  }

  Future<void> save(CompanyChange change) async {
    await _twice(() => _repo.update(change));
    await _refreshed();
  }

  Future<void> changeLogo({
    required String path,
    required String fileName,
    required String contentType,
  }) async {
    await _twice(
      () => _repo.uploadLogo(
        path: path,
        fileName: fileName,
        contentType: contentType,
      ),
    );
    await _refreshed();
  }

  Future<void> _refreshed() async {
    _ref.invalidate(companyProfileProvider);
    try {
      await _ref.read(sessionProvider.notifier).refreshMe();
    } catch (_) {
      // The change is saved; the name and logo around the app catch up on the
      // next refresh.
    }
  }
}

final companyActionsProvider = Provider<CompanyActions>(
  (ref) => CompanyActions(ref),
);
