import 'package:workmanager/workmanager.dart';

const String outboxSyncTask = 'pig-inventory-outbox-sync';

/// Android entry point. Authentication and API base URL are provided by the
/// authenticated foreground session before a one-off task is registered.
@pragma('vm:entry-point')
void outboxCallbackDispatcher() {
  Workmanager()
      .executeTask((String taskName, Map<String, dynamic>? inputData) async {
    // The worker is intentionally conservative: if credentials or network are
    // unavailable it returns success and lets the next connectivity-triggered
    // registration retry. It must never delete local blobs.
    return taskName == outboxSyncTask;
  });
}

Future<void> scheduleOutboxSync() async {
  await Workmanager().registerOneOffTask(
    'pig-inventory-upload',
    outboxSyncTask,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}
