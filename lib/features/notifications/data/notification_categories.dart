import 'package:flutter/material.dart';

/// A kind of alert (one switch in the notification settings and one filter on the
/// list): its key as the server names it, its name, a line about what it covers
/// and its icon.
@immutable
class NotificationCategory {
  const NotificationCategory(this.key, this.label, this.description, this.icon);

  final String key;
  final String label;
  final String description;
  final IconData icon;
}

abstract final class NotificationCategories {
  static const all = <NotificationCategory>[
    NotificationCategory(
      'messages',
      'Messages',
      'Chats, replies and when you are tagged',
      Icons.chat_bubble_outline_rounded,
    ),
    NotificationCategory(
      'tasks',
      'Tasks',
      'Assignments, status changes and comments',
      Icons.task_alt_rounded,
    ),
    NotificationCategory(
      'projects',
      'Projects',
      'Team changes, status, dates and stages',
      Icons.apartment_rounded,
    ),
    NotificationCategory(
      'time',
      'Time',
      'Hours submitted and approved',
      Icons.schedule_rounded,
    ),
    NotificationCategory(
      'materials',
      'Materials',
      'Material used, purchases and low stock',
      Icons.inventory_2_outlined,
    ),
    NotificationCategory(
      'procurement',
      'Purchasing',
      'Purchase requests, orders and deliveries',
      Icons.local_shipping_outlined,
    ),
    NotificationCategory(
      'finance',
      'Finance',
      'Payments, quotes, costs and budgets',
      Icons.payments_outlined,
    ),
    NotificationCategory(
      'approvals',
      'Approvals',
      'Things waiting for your decision and what was decided',
      Icons.fact_check_outlined,
    ),
    NotificationCategory(
      'equipment',
      'Equipment',
      'Equipment sent to or back from a project',
      Icons.construction_rounded,
    ),
    NotificationCategory(
      'documents',
      'Documents',
      'New, approved and rejected documents',
      Icons.description_outlined,
    ),
    NotificationCategory(
      'team',
      'Team',
      'Invites, roles and access',
      Icons.groups_2_outlined,
    ),
  ];

  static NotificationCategory? byKey(String? key) {
    if (key == null) return null;
    for (final c in all) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// The icon for an alert of [key]; a plain bell when it has no kind.
  static IconData iconFor(String? key) =>
      byKey(key)?.icon ?? Icons.notifications_none_rounded;

  /// The name for [key]; the key itself when the app does not know it.
  static String labelFor(String? key) => byKey(key)?.label ?? (key ?? 'Other');

  /// Where [key] comes in the list (unknown kinds last), for ordering.
  static int orderOf(String key) {
    final i = all.indexWhere((c) => c.key == key);
    return i < 0 ? all.length : i;
  }
}
