import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/auth/auth_api.dart';
import '../../core/auth/auth_context_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/auth_session_repository.dart';
import '../../core/network/upload_api.dart';
import '../../core/storage/app_database.dart';
import '../outbox/application/upload_package_synchronizer.dart';
import '../outbox/data/drift_outbox_repository.dart';

const String outboxSyncTask = 'pig-inventory-outbox-sync';
const String _outboxUniqueName = 'pig-inventory-upload';
const Duration _workerTokenRefreshWindow = Duration(minutes: 1);

/// Android entry point. The worker reads only the short-lived session from the
/// OS secure storage and persisted local state; no credentials are passed in
/// WorkManager inputData.
@pragma('vm:entry-point')
void outboxCallbackDispatcher() {
  Workmanager()
      .executeTask((String taskName, Map<String, dynamic>? inputData) async {
    if (taskName != outboxSyncTask) return false;
    return _runOutboxWorker();
  });
}

Future<bool> _runOutboxWorker() async {
  AppDatabase? database;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    database = await AppDatabase.open();
    final SecureAuthSessionRepository sessions = SecureAuthSessionRepository();
    final AuthSession? storedSession = await sessions.read();
    final AuthContextRepository contexts = AuthContextRepository(database);
    final AuthenticatedUser? user = await contexts.readLatest();
    if (storedSession == null || user == null) return true;

    final AuthApi authApi = AuthApi(baseUrl: _workerApiBaseUrl);
    AuthSession session = storedSession;
    if (session.accessTokenExpiresAt
        .isBefore(DateTime.now().toUtc().add(_workerTokenRefreshWindow))) {
      try {
        session = await authApi.refresh(session.refreshToken);
        await sessions.save(session);
      } on Exception {
        // The refresh token may be expired or revoked. Preserve the queued
        // evidence and wait for a foreground login instead of deleting it.
        return true;
      }
    }

    final DriftOutboxRepository repository = DriftOutboxRepository(database);
    AuthState auth = AuthState(
      session: session,
      user: user,
      isOffline: false,
    );
    final UploadPackageSynchronizer synchronizer = UploadPackageSynchronizer(
      api: UploadRemoteApi(baseUrl: _workerApiBaseUrl),
      repository: repository,
      reconnect: () async {
        try {
          final AuthSession refreshed = await authApi.refresh(auth.session.refreshToken);
          await sessions.save(refreshed);
          auth = AuthState(session: refreshed, user: user, isOffline: false);
          return auth;
        } on Exception {
          // Never discard queued media if the refresh token was revoked.
          return null;
        }
      },
    );

    // Process a bounded batch so a large queue does not exceed Android's
    // background execution window. A later scheduled run continues the queue.
    for (int index = 0; index < 20; index++) {
      final UploadSyncOutcome outcome = await synchronizer.syncNext(
        auth,
        leaseOwner: 'workmanager',
      );
      switch (outcome) {
        case UploadSyncOutcome.synced:
          continue;
        case UploadSyncOutcome.nothingToUpload:
        case UploadSyncOutcome.blocked:
          return true;
        case UploadSyncOutcome.waitingForNetwork:
        case UploadSyncOutcome.retryScheduled:
          return false;
        case UploadSyncOutcome.waitingForAuthentication:
          try {
            final AuthSession refreshed =
                await authApi.refresh(auth.session.refreshToken);
            await sessions.save(refreshed);
            await repository.retryAuthenticationWaiting(
                now: DateTime.now().toUtc());
            auth = AuthState(session: refreshed, user: user, isOffline: false);
          } on Exception {
            return true;
          }
      }
    }
    return true;
  } on SocketException {
    return false;
  } on Exception {
    // WorkManager retries transient infrastructure failures. Local evidence
    // remains durable regardless of the result returned here.
    return false;
  } finally {
    await database?.close();
  }
}

String get _workerApiBaseUrl => const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8088',
    );

Future<void> scheduleOutboxSync() async {
  await Workmanager().registerOneOffTask(
    _outboxUniqueName,
    outboxSyncTask,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
  );
}
