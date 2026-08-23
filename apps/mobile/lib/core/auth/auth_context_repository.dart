import 'dart:convert';

import 'package:drift/drift.dart';

import '../storage/app_database.dart';
import 'auth_session.dart';

class AuthContextRepository {
  AuthContextRepository(this._database);
  final AppDatabase _database;

  Future<void> save(AuthenticatedUser user) =>
      _database.into(_database.authContexts).insertOnConflictUpdate(
            AuthContextsCompanion.insert(
              subjectId: user.subjectId,
              displayName: user.displayName,
              activeOrganizationId: user.activeOrganizationId,
              activeOrganizationCode: user.activeOrganizationCode,
              activeOrganizationName: user.activeOrganizationName,
              rolesJson: jsonEncode(user.roles),
              lastVerifiedAt: user.lastVerifiedAt.toUtc(),
            ),
          );

  Future<AuthenticatedUser?> readLatest() async {
    final AuthContext? context = await (_database.select(_database.authContexts)
          ..orderBy(<OrderingTerm Function(AuthContexts)>[
            (AuthContexts table) => OrderingTerm.desc(table.lastVerifiedAt),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (context == null) return null;
    return AuthenticatedUser(
      subjectId: context.subjectId,
      displayName: context.displayName,
      activeOrganizationId: context.activeOrganizationId,
      activeOrganizationCode: context.activeOrganizationCode,
      activeOrganizationName: context.activeOrganizationName,
      roles: (jsonDecode(context.rolesJson) as List<dynamic>).cast<String>(),
      lastVerifiedAt: context.lastVerifiedAt.toUtc(),
    );
  }

  Future<void> clear() => _database.delete(_database.authContexts).go();
}
