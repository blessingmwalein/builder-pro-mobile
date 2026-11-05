import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/snack.dart';
import '../application/messaging_providers.dart';

/// Whether this person may be messaged from here: the signed-in user holds
/// `messaging.send` and it is not themselves.
bool canMessage(WidgetRef ref, String personId) =>
    ref.read(permissionsProvider).hasAny(Feature.messagingSend) &&
    ref.read(currentUserIdProvider) != personId;

/// Opens the chat with [personId] (making it when there is none yet) and shows
/// it. Failures are shown as a message. The caller keeps its own "busy" flag so a
/// second tap cannot start a second chat.
Future<void> openChatWith(
  BuildContext context,
  WidgetRef ref,
  String personId,
) async {
  try {
    final id = await ref.read(chatActionsProvider).openDirect(personId);
    if (context.mounted) context.push('/messages/$id');
  } on AppException catch (e) {
    if (context.mounted) Snack.error(context, e);
  }
}
