import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/features/capture/application/abandon_blocked_capture_draft.dart';

void main() {
  test('abandons only an uncommitted blocked draft and preserves its rows',
      () async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final DateTime now = DateTime.utc(2026, 9, 12);
    await database
        .into(database.captureDrafts)
        .insert(CaptureDraftsCompanion.insert(
          id: 'draft-1',
          organizationId: 'organization-1',
          penId: 'pen-1',
          captureKind: 'single',
          businessDate: now,
          createdAt: now,
          updatedAt: now,
        ));
    await database
        .into(database.outboxEntries)
        .insert(OutboxEntriesCompanion.insert(
          packageId: 'package-1',
          draftId: 'draft-1',
          idempotencyKey: 'idempotency-1',
          manifestJson: '{}',
          state: const drift.Value<String>('blocked'),
          serverPackageId: const drift.Value<String>('server-package-1'),
          createdAt: now,
          updatedAt: now,
        ));

    await AbandonBlockedCaptureDraft(database).execute('draft-1', now: now);

    final OutboxEntry entry = await (database.select(database.outboxEntries)
          ..where((OutboxEntries row) => row.packageId.equals('package-1')))
        .getSingle();
    final CaptureDraft draft = await (database.select(database.captureDrafts)
          ..where((CaptureDrafts row) => row.id.equals('draft-1')))
        .getSingle();
    expect(entry.state, 'abandoned');
    expect(entry.serverPackageId, 'server-package-1');
    expect(draft.state, 'abandoned');
  });

  test('refuses to abandon a draft that already has a server session',
      () async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final DateTime now = DateTime.utc(2026, 9, 12);
    await database
        .into(database.captureDrafts)
        .insert(CaptureDraftsCompanion.insert(
          id: 'draft-2',
          organizationId: 'organization-1',
          penId: 'pen-1',
          captureKind: 'single',
          businessDate: now,
          createdAt: now,
          updatedAt: now,
        ));
    await database
        .into(database.outboxEntries)
        .insert(OutboxEntriesCompanion.insert(
          packageId: 'package-2',
          draftId: 'draft-2',
          idempotencyKey: 'idempotency-2',
          manifestJson: '{}',
          state: const drift.Value<String>('blocked'),
          sessionId: const drift.Value<String>('session-2'),
          createdAt: now,
          updatedAt: now,
        ));

    expect(
      () => AbandonBlockedCaptureDraft(database).execute('draft-2', now: now),
      throwsA(isA<StateError>()),
    );
  });
}
