import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/report_models.dart';
import '../data/reports_repository.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);

/// Which projects are behind. Reloads when the app returns to the front.
final delayReportProvider = FutureProvider.autoDispose<DelayReport>((ref) {
  ref.watch(currentUserIdProvider);
  ref.watch(appResumeProvider);
  return ref.watch(reportsRepositoryProvider).delays();
});

/// Task completion and hours worked per project.
final productivityReportProvider =
    FutureProvider.autoDispose<ProductivityReport>((ref) {
      ref.watch(currentUserIdProvider);
      ref.watch(appResumeProvider);
      return ref.watch(reportsRepositoryProvider).productivity();
    });
