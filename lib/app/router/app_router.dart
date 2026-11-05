import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../features/authentication/presentation/forgot_password_screen.dart';
import '../../features/authentication/presentation/login_screen.dart';
import '../../features/approvals/presentation/approvals_screen.dart';
import '../../features/authentication/presentation/status_screens.dart';
import '../../features/finance/presentation/finance_detail_screen.dart';
import '../../features/finance/presentation/finance_screen.dart';
import '../../features/finance/presentation/invoices_screens.dart';
import '../../features/finance/presentation/project_costs_screen.dart';
import '../../features/finance/presentation/record_cost_screen.dart';
import '../../features/finance/presentation/record_payment_screen.dart';
import '../../features/finance/presentation/quotes_screens.dart';
import '../../features/materials/data/material_models.dart';
import '../../features/materials/presentation/log_usage_screen.dart';
import '../../features/materials/presentation/materials_screen.dart';
import '../../features/messaging/presentation/conversations_screen.dart';
import '../../features/messaging/presentation/notifications_screen.dart';
import '../../features/notifications/presentation/notification_settings_screen.dart';
import '../../features/messaging/presentation/image_viewer_screen.dart';
import '../../features/messaging/presentation/new_chat_screen.dart';
import '../../features/messaging/presentation/thread_screen.dart';
import '../../features/projects/presentation/project_detail_screen.dart';
import '../../features/projects/presentation/project_edit_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/settings/presentation/edit_profile_screen.dart';
import '../../features/team/presentation/team_screen.dart';
import '../../features/change_requests/presentation/change_request_decision_screen.dart';
import '../../features/change_requests/presentation/change_request_detail_screen.dart';
import '../../features/change_requests/presentation/new_change_request_screen.dart';
import '../../features/clients/presentation/client_detail_screen.dart';
import '../../features/clients/presentation/client_form_screen.dart';
import '../../features/clients/presentation/clients_screen.dart';
import '../../features/equipment/presentation/assign_equipment_screen.dart';
import '../../features/equipment/presentation/equipment_detail_screen.dart';
import '../../features/equipment/presentation/equipment_form_screen.dart';
import '../../features/equipment/presentation/equipment_screen.dart';
import '../../features/purchasing/presentation/edit_purchase_order_screen.dart';
import '../../features/purchasing/presentation/new_purchase_request_screen.dart';
import '../../features/purchasing/presentation/purchase_order_detail_screen.dart';
import '../../features/purchasing/presentation/purchase_request_detail_screen.dart';
import '../../features/purchasing/presentation/purchasing_screen.dart';
import '../../features/purchasing/presentation/receive_delivery_screen.dart';
import '../../features/projects/presentation/projects_screen.dart';
import '../../features/requests/presentation/requests_screen.dart';
import '../../features/settings/presentation/company_edit_screen.dart';
import '../../features/settings/presentation/company_profile_screen.dart';
import '../../features/settings/presentation/more_screen.dart';
import '../../features/tasks/data/task_models.dart';
import '../../features/tasks/presentation/task_detail_screen.dart';
import '../../features/tasks/presentation/task_form_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/today/presentation/today_screen.dart';
import '../../features/time/presentation/clock_screen.dart';
import '../shell/app_shell.dart';
import 'destinations.dart';
import 'route_guard.dart';
import '../../features/finance/presentation/invoice_form_screen.dart';
import '../../features/finance/presentation/quote_form_screen.dart';
import '../../features/materials/presentation/material_form_screen.dart';
import '../../features/materials/presentation/purchases_screen.dart';
import '../../features/materials/presentation/record_purchase_screen.dart';
import '../../features/materials/presentation/stock_count_screen.dart';
import '../../features/materials/presentation/suppliers_screens.dart';
import '../../features/purchasing/presentation/purchase_order_form_screen.dart';
import '../../features/finance/presentation/budget_edit_screen.dart';

/// Detail screens use this so they open full-screen over the bottom bar.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever the session (auth state OR permissions) changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        computeRedirect(ref.read(sessionProvider), state.uri.path),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.subscriptionBlocked,
        builder: (_, _) => const SubscriptionBlockedScreen(),
      ),
      GoRoute(
        path: Routes.startupFailed,
        builder: (_, _) => const StartupFailedScreen(),
      ),
      GoRoute(
        path: Routes.denied,
        builder: (_, _) => const AccessDeniedScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: clockDestination.path,
                builder: (_, _) => const ClockScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: tasksDestination.path,
                builder: (_, _) => const TasksScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) =>
                        TaskDetailScreen(taskId: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: _rootNavigatorKey,
                        // The task is passed by the detail screen; a bare deep
                        // link has none, so it opens the detail instead.
                        redirect: (_, state) => state.extra is TaskItem
                            ? null
                            : '/tasks/${state.pathParameters['id']}',
                        builder: (_, state) {
                          final task = state.extra! as TaskItem;
                          return TaskFormScreen(
                            projectId: task.project.id,
                            editing: task,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: materialsDestination.path,
                builder: (_, _) => const MaterialsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const MaterialFormScreen(),
                  ),
                  GoRoute(
                    path: 'edit',
                    parentNavigatorKey: _rootNavigatorKey,
                    redirect: (_, state) => state.extra is MaterialItem
                        ? null
                        : materialsDestination.path,
                    builder: (_, state) => MaterialFormScreen(
                      editing: state.extra! as MaterialItem,
                    ),
                  ),
                  GoRoute(
                    path: 'suppliers',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const SuppliersScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, _) => const SupplierFormScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'purchases',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const PurchasesScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, _) => const RecordPurchaseScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'count',
                    parentNavigatorKey: _rootNavigatorKey,
                    redirect: (_, state) => state.extra is MaterialItem
                        ? null
                        : materialsDestination.path,
                    builder: (_, state) => StockCountScreen(
                      material: state.extra! as MaterialItem,
                    ),
                  ),
                  GoRoute(
                    path: 'log',
                    parentNavigatorKey: _rootNavigatorKey,
                    // The item is passed by the catalog; a bare deep link has none.
                    redirect: (_, state) => state.extra is MaterialItem
                        ? null
                        : materialsDestination.path,
                    builder: (_, state) =>
                        LogUsageScreen(material: state.extra! as MaterialItem),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: messagesDestination.path,
                builder: (_, _) => const ConversationsScreen(),
                routes: [
                  // The fixed paths come before ':id' so they are matched first.
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const NewChatScreen(),
                  ),
                  GoRoute(
                    path: 'image',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) {
                      final args = state.extra;
                      return ImageViewerScreen(
                        args: args is ImageViewerArgs
                            ? args
                            : const ImageViewerArgs(images: [], index: 0),
                      );
                    },
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => ThreadScreen(
                      conversationId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: todayDestination.path,
                builder: (_, _) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: projectsDestination.path,
                builder: (_, _) => const ProjectsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => ProjectDetailScreen(
                      projectId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'new-task',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => TaskFormScreen(
                          projectId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => ProjectEditScreen(
                          projectId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'budget',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => BudgetEditScreen(
                          projectId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'costs',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => ProjectCostsScreen(
                          projectId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'new',
                            parentNavigatorKey: _rootNavigatorKey,
                            builder: (_, state) => RecordCostScreen(
                              projectId: state.pathParameters['id']!,
                              initialCategoryId:
                                  state.uri.queryParameters['category'],
                            ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'new-change-request',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => NewChangeRequestScreen(
                          projectId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'change-requests/:crId',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => ChangeRequestDetailScreen(
                          projectId: state.pathParameters['id']!,
                          requestId: state.pathParameters['crId']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'review',
                            parentNavigatorKey: _rootNavigatorKey,
                            builder: (_, state) => ChangeRequestDecisionScreen(
                              projectId: state.pathParameters['id']!,
                              requestId: state.pathParameters['crId']!,
                              decision: CrDecision.review,
                            ),
                          ),
                          GoRoute(
                            path: 'approve',
                            parentNavigatorKey: _rootNavigatorKey,
                            builder: (_, state) => ChangeRequestDecisionScreen(
                              projectId: state.pathParameters['id']!,
                              requestId: state.pathParameters['crId']!,
                              decision: CrDecision.approve,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: approvalsDestination.path,
                builder: (_, _) => const ApprovalsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: financeDestination.path,
                builder: (_, _) => const FinanceScreen(),
                routes: [
                  GoRoute(
                    path: 'detail/:tab',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => FinanceDetailScreen(
                      tab: MoneyTab.parse(state.pathParameters['tab']),
                      projectId: state.uri.queryParameters['project'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: invoicesDestination.path,
                builder: (_, _) => const InvoicesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => InvoiceFormScreen(
                      quoteId: state.uri.queryParameters['quoteId'],
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => InvoiceDetailScreen(
                      invoiceId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'pay',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => RecordPaymentScreen(
                          invoiceId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: quotesDestination.path,
                builder: (_, _) => const QuotesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const QuoteFormScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) =>
                        QuoteDetailScreen(quoteId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: requestsDestination.path,
                builder: (_, _) => const RequestsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: purchasingDestination.path,
                builder: (_, _) => const PurchasingScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const NewPurchaseRequestScreen(),
                  ),
                  GoRoute(
                    path: 'requests/:id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => PurchaseRequestDetailScreen(
                      requestId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'order',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => NewPurchaseOrderScreen(
                          requestId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'orders/:id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => PurchaseOrderDetailScreen(
                      orderId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'receive',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => ReceiveDeliveryScreen(
                          orderId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => EditPurchaseOrderScreen(
                          orderId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: equipmentDestination.path,
                builder: (_, _) => const EquipmentScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const EquipmentFormScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => EquipmentDetailScreen(
                      equipmentId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => EquipmentFormScreen(
                          equipmentId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'assign',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => AssignEquipmentScreen(
                          equipmentId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: clientsDestination.path,
                builder: (_, _) => const ClientsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const ClientFormScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => ClientDetailScreen(
                      clientId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => ClientFormScreen(
                          clientId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: reportsDestination.path,
                builder: (_, _) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: teamDestination.path,
                builder: (_, _) => const TeamScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.more,
                builder: (_, _) => const MoreScreen(),
                routes: [
                  GoRoute(
                    path: 'notifications',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const NotificationsScreen(),
                    routes: [
                      GoRoute(
                        path: 'settings',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, _) => const NotificationSettingsScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'profile',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'company',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const CompanyProfileScreen(),
                    routes: [
                      GoRoute(
                        path: 'edit/:section',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => CompanyEditScreen(
                          section: state.pathParameters['section']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
