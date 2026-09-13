import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';

/// Stops retrying a terminally rejected local package so the operator can
/// capture a new image for the same pen and business date. It deliberately
/// retains local media files and never touches server-side evidence.
class AbandonBlockedCaptureDraft {
  AbandonBlockedCaptureDraft(this._database);

  final AppDatabase _database;

  Future<void> execute(String draftId, {DateTime? now}) =>
      _database.transaction(() async {
        final OutboxEntry? entry =
            await (_database.select(_database.outboxEntries)
                  ..where((OutboxEntries row) => row.draftId.equals(draftId)))
                .getSingleOrNull();
        if (entry == null ||
            entry.state != 'blocked' ||
            entry.sessionId != null) {
          throw StateError(
              'Only an uncommitted blocked draft can be abandoned');
        }

        final DateTime updatedAt = (now ?? DateTime.now()).toUtc();
        await (_database.update(_database.outboxEntries)
              ..where(
                  (OutboxEntries row) => row.packageId.equals(entry.packageId)))
            .write(OutboxEntriesCompanion(
          state: const Value<String>('abandoned'),
          nextAttemptAt: const Value<DateTime?>(null),
          leaseOwner: const Value<String?>(null),
          leaseExpiresAt: const Value<DateTime?>(null),
          updatedAt: Value<DateTime>(updatedAt),
        ));
        await (_database.update(_database.captureDrafts)
              ..where((CaptureDrafts row) => row.id.equals(draftId)))
            .write(CaptureDraftsCompanion(
          state: const Value<String>('abandoned'),
          updatedAt: Value<DateTime>(updatedAt),
        ));
      });
}
