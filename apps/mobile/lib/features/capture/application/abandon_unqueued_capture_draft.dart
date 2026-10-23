import 'package:drift/drift.dart';
import '../../../core/storage/app_database.dart';

class AbandonUnqueuedCaptureDraft {
  AbandonUnqueuedCaptureDraft(this.database);
  final AppDatabase database;

  Future<void> execute(String draftId, {required String organizationId}) =>
      database.transaction(() async {
        final draft = await (database.select(database.captureDrafts)
              ..where((r) => r.id.equals(draftId)))
            .getSingle();
        final queue = await (database.select(database.outboxEntries)
              ..where((r) => r.draftId.equals(draftId)))
            .get();
        if (draft.organizationId != organizationId ||
            draft.state != 'draft' ||
            queue.isNotEmpty) {
          throw StateError('只有当前组织尚未入队的草稿可放弃');
        }
        await (database.update(database.captureDrafts)
              ..where((r) => r.id.equals(draftId)))
            .write(CaptureDraftsCompanion(
                state: const Value('abandoned'),
                updatedAt: Value(DateTime.now().toUtc())));
      });
}
