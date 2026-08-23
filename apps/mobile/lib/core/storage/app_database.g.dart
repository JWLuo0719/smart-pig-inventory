// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AuthContextsTable extends AuthContexts
    with TableInfo<$AuthContextsTable, AuthContext> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuthContextsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta =
      const VerificationMeta('subjectId');
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
      'subject_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _activeOrganizationIdMeta =
      const VerificationMeta('activeOrganizationId');
  @override
  late final GeneratedColumn<String> activeOrganizationId =
      GeneratedColumn<String>('active_organization_id', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _activeOrganizationCodeMeta =
      const VerificationMeta('activeOrganizationCode');
  @override
  late final GeneratedColumn<String> activeOrganizationCode =
      GeneratedColumn<String>('active_organization_code', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _activeOrganizationNameMeta =
      const VerificationMeta('activeOrganizationName');
  @override
  late final GeneratedColumn<String> activeOrganizationName =
      GeneratedColumn<String>('active_organization_name', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rolesJsonMeta =
      const VerificationMeta('rolesJson');
  @override
  late final GeneratedColumn<String> rolesJson = GeneratedColumn<String>(
      'roles_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastVerifiedAtMeta =
      const VerificationMeta('lastVerifiedAt');
  @override
  late final GeneratedColumn<DateTime> lastVerifiedAt =
      GeneratedColumn<DateTime>('last_verified_at', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        subjectId,
        displayName,
        activeOrganizationId,
        activeOrganizationCode,
        activeOrganizationName,
        rolesJson,
        lastVerifiedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'auth_contexts';
  @override
  VerificationContext validateIntegrity(Insertable<AuthContext> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(_subjectIdMeta,
          subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta));
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('active_organization_id')) {
      context.handle(
          _activeOrganizationIdMeta,
          activeOrganizationId.isAcceptableOrUnknown(
              data['active_organization_id']!, _activeOrganizationIdMeta));
    } else if (isInserting) {
      context.missing(_activeOrganizationIdMeta);
    }
    if (data.containsKey('active_organization_code')) {
      context.handle(
          _activeOrganizationCodeMeta,
          activeOrganizationCode.isAcceptableOrUnknown(
              data['active_organization_code']!, _activeOrganizationCodeMeta));
    } else if (isInserting) {
      context.missing(_activeOrganizationCodeMeta);
    }
    if (data.containsKey('active_organization_name')) {
      context.handle(
          _activeOrganizationNameMeta,
          activeOrganizationName.isAcceptableOrUnknown(
              data['active_organization_name']!, _activeOrganizationNameMeta));
    } else if (isInserting) {
      context.missing(_activeOrganizationNameMeta);
    }
    if (data.containsKey('roles_json')) {
      context.handle(_rolesJsonMeta,
          rolesJson.isAcceptableOrUnknown(data['roles_json']!, _rolesJsonMeta));
    } else if (isInserting) {
      context.missing(_rolesJsonMeta);
    }
    if (data.containsKey('last_verified_at')) {
      context.handle(
          _lastVerifiedAtMeta,
          lastVerifiedAt.isAcceptableOrUnknown(
              data['last_verified_at']!, _lastVerifiedAtMeta));
    } else if (isInserting) {
      context.missing(_lastVerifiedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId};
  @override
  AuthContext map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuthContext(
      subjectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject_id'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      activeOrganizationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}active_organization_id'])!,
      activeOrganizationCode: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}active_organization_code'])!,
      activeOrganizationName: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}active_organization_name'])!,
      rolesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}roles_json'])!,
      lastVerifiedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_verified_at'])!,
    );
  }

  @override
  $AuthContextsTable createAlias(String alias) {
    return $AuthContextsTable(attachedDatabase, alias);
  }
}

class AuthContext extends DataClass implements Insertable<AuthContext> {
  final String subjectId;
  final String displayName;
  final String activeOrganizationId;
  final String activeOrganizationCode;
  final String activeOrganizationName;
  final String rolesJson;
  final DateTime lastVerifiedAt;
  const AuthContext(
      {required this.subjectId,
      required this.displayName,
      required this.activeOrganizationId,
      required this.activeOrganizationCode,
      required this.activeOrganizationName,
      required this.rolesJson,
      required this.lastVerifiedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['display_name'] = Variable<String>(displayName);
    map['active_organization_id'] = Variable<String>(activeOrganizationId);
    map['active_organization_code'] = Variable<String>(activeOrganizationCode);
    map['active_organization_name'] = Variable<String>(activeOrganizationName);
    map['roles_json'] = Variable<String>(rolesJson);
    map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt);
    return map;
  }

  AuthContextsCompanion toCompanion(bool nullToAbsent) {
    return AuthContextsCompanion(
      subjectId: Value(subjectId),
      displayName: Value(displayName),
      activeOrganizationId: Value(activeOrganizationId),
      activeOrganizationCode: Value(activeOrganizationCode),
      activeOrganizationName: Value(activeOrganizationName),
      rolesJson: Value(rolesJson),
      lastVerifiedAt: Value(lastVerifiedAt),
    );
  }

  factory AuthContext.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuthContext(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      activeOrganizationId:
          serializer.fromJson<String>(json['activeOrganizationId']),
      activeOrganizationCode:
          serializer.fromJson<String>(json['activeOrganizationCode']),
      activeOrganizationName:
          serializer.fromJson<String>(json['activeOrganizationName']),
      rolesJson: serializer.fromJson<String>(json['rolesJson']),
      lastVerifiedAt: serializer.fromJson<DateTime>(json['lastVerifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'displayName': serializer.toJson<String>(displayName),
      'activeOrganizationId': serializer.toJson<String>(activeOrganizationId),
      'activeOrganizationCode':
          serializer.toJson<String>(activeOrganizationCode),
      'activeOrganizationName':
          serializer.toJson<String>(activeOrganizationName),
      'rolesJson': serializer.toJson<String>(rolesJson),
      'lastVerifiedAt': serializer.toJson<DateTime>(lastVerifiedAt),
    };
  }

  AuthContext copyWith(
          {String? subjectId,
          String? displayName,
          String? activeOrganizationId,
          String? activeOrganizationCode,
          String? activeOrganizationName,
          String? rolesJson,
          DateTime? lastVerifiedAt}) =>
      AuthContext(
        subjectId: subjectId ?? this.subjectId,
        displayName: displayName ?? this.displayName,
        activeOrganizationId: activeOrganizationId ?? this.activeOrganizationId,
        activeOrganizationCode:
            activeOrganizationCode ?? this.activeOrganizationCode,
        activeOrganizationName:
            activeOrganizationName ?? this.activeOrganizationName,
        rolesJson: rolesJson ?? this.rolesJson,
        lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      );
  AuthContext copyWithCompanion(AuthContextsCompanion data) {
    return AuthContext(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      activeOrganizationId: data.activeOrganizationId.present
          ? data.activeOrganizationId.value
          : this.activeOrganizationId,
      activeOrganizationCode: data.activeOrganizationCode.present
          ? data.activeOrganizationCode.value
          : this.activeOrganizationCode,
      activeOrganizationName: data.activeOrganizationName.present
          ? data.activeOrganizationName.value
          : this.activeOrganizationName,
      rolesJson: data.rolesJson.present ? data.rolesJson.value : this.rolesJson,
      lastVerifiedAt: data.lastVerifiedAt.present
          ? data.lastVerifiedAt.value
          : this.lastVerifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuthContext(')
          ..write('subjectId: $subjectId, ')
          ..write('displayName: $displayName, ')
          ..write('activeOrganizationId: $activeOrganizationId, ')
          ..write('activeOrganizationCode: $activeOrganizationCode, ')
          ..write('activeOrganizationName: $activeOrganizationName, ')
          ..write('rolesJson: $rolesJson, ')
          ..write('lastVerifiedAt: $lastVerifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      subjectId,
      displayName,
      activeOrganizationId,
      activeOrganizationCode,
      activeOrganizationName,
      rolesJson,
      lastVerifiedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthContext &&
          other.subjectId == this.subjectId &&
          other.displayName == this.displayName &&
          other.activeOrganizationId == this.activeOrganizationId &&
          other.activeOrganizationCode == this.activeOrganizationCode &&
          other.activeOrganizationName == this.activeOrganizationName &&
          other.rolesJson == this.rolesJson &&
          other.lastVerifiedAt == this.lastVerifiedAt);
}

class AuthContextsCompanion extends UpdateCompanion<AuthContext> {
  final Value<String> subjectId;
  final Value<String> displayName;
  final Value<String> activeOrganizationId;
  final Value<String> activeOrganizationCode;
  final Value<String> activeOrganizationName;
  final Value<String> rolesJson;
  final Value<DateTime> lastVerifiedAt;
  final Value<int> rowid;
  const AuthContextsCompanion({
    this.subjectId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.activeOrganizationId = const Value.absent(),
    this.activeOrganizationCode = const Value.absent(),
    this.activeOrganizationName = const Value.absent(),
    this.rolesJson = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuthContextsCompanion.insert({
    required String subjectId,
    required String displayName,
    required String activeOrganizationId,
    required String activeOrganizationCode,
    required String activeOrganizationName,
    required String rolesJson,
    required DateTime lastVerifiedAt,
    this.rowid = const Value.absent(),
  })  : subjectId = Value(subjectId),
        displayName = Value(displayName),
        activeOrganizationId = Value(activeOrganizationId),
        activeOrganizationCode = Value(activeOrganizationCode),
        activeOrganizationName = Value(activeOrganizationName),
        rolesJson = Value(rolesJson),
        lastVerifiedAt = Value(lastVerifiedAt);
  static Insertable<AuthContext> custom({
    Expression<String>? subjectId,
    Expression<String>? displayName,
    Expression<String>? activeOrganizationId,
    Expression<String>? activeOrganizationCode,
    Expression<String>? activeOrganizationName,
    Expression<String>? rolesJson,
    Expression<DateTime>? lastVerifiedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (displayName != null) 'display_name': displayName,
      if (activeOrganizationId != null)
        'active_organization_id': activeOrganizationId,
      if (activeOrganizationCode != null)
        'active_organization_code': activeOrganizationCode,
      if (activeOrganizationName != null)
        'active_organization_name': activeOrganizationName,
      if (rolesJson != null) 'roles_json': rolesJson,
      if (lastVerifiedAt != null) 'last_verified_at': lastVerifiedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuthContextsCompanion copyWith(
      {Value<String>? subjectId,
      Value<String>? displayName,
      Value<String>? activeOrganizationId,
      Value<String>? activeOrganizationCode,
      Value<String>? activeOrganizationName,
      Value<String>? rolesJson,
      Value<DateTime>? lastVerifiedAt,
      Value<int>? rowid}) {
    return AuthContextsCompanion(
      subjectId: subjectId ?? this.subjectId,
      displayName: displayName ?? this.displayName,
      activeOrganizationId: activeOrganizationId ?? this.activeOrganizationId,
      activeOrganizationCode:
          activeOrganizationCode ?? this.activeOrganizationCode,
      activeOrganizationName:
          activeOrganizationName ?? this.activeOrganizationName,
      rolesJson: rolesJson ?? this.rolesJson,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (activeOrganizationId.present) {
      map['active_organization_id'] =
          Variable<String>(activeOrganizationId.value);
    }
    if (activeOrganizationCode.present) {
      map['active_organization_code'] =
          Variable<String>(activeOrganizationCode.value);
    }
    if (activeOrganizationName.present) {
      map['active_organization_name'] =
          Variable<String>(activeOrganizationName.value);
    }
    if (rolesJson.present) {
      map['roles_json'] = Variable<String>(rolesJson.value);
    }
    if (lastVerifiedAt.present) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuthContextsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('displayName: $displayName, ')
          ..write('activeOrganizationId: $activeOrganizationId, ')
          ..write('activeOrganizationCode: $activeOrganizationCode, ')
          ..write('activeOrganizationName: $activeOrganizationName, ')
          ..write('rolesJson: $rolesJson, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedOrganizationsTable extends CachedOrganizations
    with TableInfo<$CachedOrganizationsTable, CachedOrganization> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedOrganizationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
      'code', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _syncVersionMeta =
      const VerificationMeta('syncVersion');
  @override
  late final GeneratedColumn<int> syncVersion = GeneratedColumn<int>(
      'sync_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, code, name, enabled, syncVersion, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_organizations';
  @override
  VerificationContext validateIntegrity(Insertable<CachedOrganization> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
          _codeMeta, code.isAcceptableOrUnknown(data['code']!, _codeMeta));
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('sync_version')) {
      context.handle(
          _syncVersionMeta,
          syncVersion.isAcceptableOrUnknown(
              data['sync_version']!, _syncVersionMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedOrganization map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedOrganization(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      code: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}code'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      syncVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sync_version'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at'])!,
    );
  }

  @override
  $CachedOrganizationsTable createAlias(String alias) {
    return $CachedOrganizationsTable(attachedDatabase, alias);
  }
}

class CachedOrganization extends DataClass
    implements Insertable<CachedOrganization> {
  final String id;
  final String code;
  final String name;
  final bool enabled;
  final int syncVersion;
  final DateTime syncedAt;
  const CachedOrganization(
      {required this.id,
      required this.code,
      required this.name,
      required this.enabled,
      required this.syncVersion,
      required this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['enabled'] = Variable<bool>(enabled);
    map['sync_version'] = Variable<int>(syncVersion);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    return map;
  }

  CachedOrganizationsCompanion toCompanion(bool nullToAbsent) {
    return CachedOrganizationsCompanion(
      id: Value(id),
      code: Value(code),
      name: Value(name),
      enabled: Value(enabled),
      syncVersion: Value(syncVersion),
      syncedAt: Value(syncedAt),
    );
  }

  factory CachedOrganization.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedOrganization(
      id: serializer.fromJson<String>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      syncVersion: serializer.fromJson<int>(json['syncVersion']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'enabled': serializer.toJson<bool>(enabled),
      'syncVersion': serializer.toJson<int>(syncVersion),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
    };
  }

  CachedOrganization copyWith(
          {String? id,
          String? code,
          String? name,
          bool? enabled,
          int? syncVersion,
          DateTime? syncedAt}) =>
      CachedOrganization(
        id: id ?? this.id,
        code: code ?? this.code,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        syncVersion: syncVersion ?? this.syncVersion,
        syncedAt: syncedAt ?? this.syncedAt,
      );
  CachedOrganization copyWithCompanion(CachedOrganizationsCompanion data) {
    return CachedOrganization(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      syncVersion:
          data.syncVersion.present ? data.syncVersion.value : this.syncVersion,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedOrganization(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('syncVersion: $syncVersion, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, code, name, enabled, syncVersion, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedOrganization &&
          other.id == this.id &&
          other.code == this.code &&
          other.name == this.name &&
          other.enabled == this.enabled &&
          other.syncVersion == this.syncVersion &&
          other.syncedAt == this.syncedAt);
}

class CachedOrganizationsCompanion extends UpdateCompanion<CachedOrganization> {
  final Value<String> id;
  final Value<String> code;
  final Value<String> name;
  final Value<bool> enabled;
  final Value<int> syncVersion;
  final Value<DateTime> syncedAt;
  final Value<int> rowid;
  const CachedOrganizationsCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.enabled = const Value.absent(),
    this.syncVersion = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedOrganizationsCompanion.insert({
    required String id,
    required String code,
    required String name,
    this.enabled = const Value.absent(),
    this.syncVersion = const Value.absent(),
    required DateTime syncedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        code = Value(code),
        name = Value(name),
        syncedAt = Value(syncedAt);
  static Insertable<CachedOrganization> custom({
    Expression<String>? id,
    Expression<String>? code,
    Expression<String>? name,
    Expression<bool>? enabled,
    Expression<int>? syncVersion,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (enabled != null) 'enabled': enabled,
      if (syncVersion != null) 'sync_version': syncVersion,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedOrganizationsCompanion copyWith(
      {Value<String>? id,
      Value<String>? code,
      Value<String>? name,
      Value<bool>? enabled,
      Value<int>? syncVersion,
      Value<DateTime>? syncedAt,
      Value<int>? rowid}) {
    return CachedOrganizationsCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      syncVersion: syncVersion ?? this.syncVersion,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (syncVersion.present) {
      map['sync_version'] = Variable<int>(syncVersion.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedOrganizationsCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('syncVersion: $syncVersion, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedBuildingsTable extends CachedBuildings
    with TableInfo<$CachedBuildingsTable, CachedBuilding> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedBuildingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _organizationIdMeta =
      const VerificationMeta('organizationId');
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
      'organization_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
      'code', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _syncVersionMeta =
      const VerificationMeta('syncVersion');
  @override
  late final GeneratedColumn<int> syncVersion = GeneratedColumn<int>(
      'sync_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, organizationId, code, name, enabled, syncVersion];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_buildings';
  @override
  VerificationContext validateIntegrity(Insertable<CachedBuilding> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
          _organizationIdMeta,
          organizationId.isAcceptableOrUnknown(
              data['organization_id']!, _organizationIdMeta));
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
          _codeMeta, code.isAcceptableOrUnknown(data['code']!, _codeMeta));
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('sync_version')) {
      context.handle(
          _syncVersionMeta,
          syncVersion.isAcceptableOrUnknown(
              data['sync_version']!, _syncVersionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedBuilding map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedBuilding(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      organizationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}organization_id'])!,
      code: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}code'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      syncVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sync_version'])!,
    );
  }

  @override
  $CachedBuildingsTable createAlias(String alias) {
    return $CachedBuildingsTable(attachedDatabase, alias);
  }
}

class CachedBuilding extends DataClass implements Insertable<CachedBuilding> {
  final String id;
  final String organizationId;
  final String code;
  final String name;
  final bool enabled;
  final int syncVersion;
  const CachedBuilding(
      {required this.id,
      required this.organizationId,
      required this.code,
      required this.name,
      required this.enabled,
      required this.syncVersion});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['enabled'] = Variable<bool>(enabled);
    map['sync_version'] = Variable<int>(syncVersion);
    return map;
  }

  CachedBuildingsCompanion toCompanion(bool nullToAbsent) {
    return CachedBuildingsCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      code: Value(code),
      name: Value(name),
      enabled: Value(enabled),
      syncVersion: Value(syncVersion),
    );
  }

  factory CachedBuilding.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedBuilding(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      syncVersion: serializer.fromJson<int>(json['syncVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'enabled': serializer.toJson<bool>(enabled),
      'syncVersion': serializer.toJson<int>(syncVersion),
    };
  }

  CachedBuilding copyWith(
          {String? id,
          String? organizationId,
          String? code,
          String? name,
          bool? enabled,
          int? syncVersion}) =>
      CachedBuilding(
        id: id ?? this.id,
        organizationId: organizationId ?? this.organizationId,
        code: code ?? this.code,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        syncVersion: syncVersion ?? this.syncVersion,
      );
  CachedBuilding copyWithCompanion(CachedBuildingsCompanion data) {
    return CachedBuilding(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      syncVersion:
          data.syncVersion.present ? data.syncVersion.value : this.syncVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedBuilding(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('syncVersion: $syncVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, organizationId, code, name, enabled, syncVersion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedBuilding &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.code == this.code &&
          other.name == this.name &&
          other.enabled == this.enabled &&
          other.syncVersion == this.syncVersion);
}

class CachedBuildingsCompanion extends UpdateCompanion<CachedBuilding> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> code;
  final Value<String> name;
  final Value<bool> enabled;
  final Value<int> syncVersion;
  final Value<int> rowid;
  const CachedBuildingsCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.enabled = const Value.absent(),
    this.syncVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedBuildingsCompanion.insert({
    required String id,
    required String organizationId,
    required String code,
    required String name,
    this.enabled = const Value.absent(),
    this.syncVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        organizationId = Value(organizationId),
        code = Value(code),
        name = Value(name);
  static Insertable<CachedBuilding> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<bool>? enabled,
    Expression<int>? syncVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (enabled != null) 'enabled': enabled,
      if (syncVersion != null) 'sync_version': syncVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedBuildingsCompanion copyWith(
      {Value<String>? id,
      Value<String>? organizationId,
      Value<String>? code,
      Value<String>? name,
      Value<bool>? enabled,
      Value<int>? syncVersion,
      Value<int>? rowid}) {
    return CachedBuildingsCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      code: code ?? this.code,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      syncVersion: syncVersion ?? this.syncVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (syncVersion.present) {
      map['sync_version'] = Variable<int>(syncVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedBuildingsCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('syncVersion: $syncVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPensTable extends CachedPens
    with TableInfo<$CachedPensTable, CachedPen> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPensTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _buildingIdMeta =
      const VerificationMeta('buildingId');
  @override
  late final GeneratedColumn<String> buildingId = GeneratedColumn<String>(
      'building_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
      'code', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _syncVersionMeta =
      const VerificationMeta('syncVersion');
  @override
  late final GeneratedColumn<int> syncVersion = GeneratedColumn<int>(
      'sync_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, buildingId, code, name, enabled, syncVersion];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_pens';
  @override
  VerificationContext validateIntegrity(Insertable<CachedPen> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('building_id')) {
      context.handle(
          _buildingIdMeta,
          buildingId.isAcceptableOrUnknown(
              data['building_id']!, _buildingIdMeta));
    } else if (isInserting) {
      context.missing(_buildingIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
          _codeMeta, code.isAcceptableOrUnknown(data['code']!, _codeMeta));
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('sync_version')) {
      context.handle(
          _syncVersionMeta,
          syncVersion.isAcceptableOrUnknown(
              data['sync_version']!, _syncVersionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedPen map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPen(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      buildingId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}building_id'])!,
      code: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}code'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      syncVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sync_version'])!,
    );
  }

  @override
  $CachedPensTable createAlias(String alias) {
    return $CachedPensTable(attachedDatabase, alias);
  }
}

class CachedPen extends DataClass implements Insertable<CachedPen> {
  final String id;
  final String buildingId;
  final String code;
  final String name;
  final bool enabled;
  final int syncVersion;
  const CachedPen(
      {required this.id,
      required this.buildingId,
      required this.code,
      required this.name,
      required this.enabled,
      required this.syncVersion});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['building_id'] = Variable<String>(buildingId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['enabled'] = Variable<bool>(enabled);
    map['sync_version'] = Variable<int>(syncVersion);
    return map;
  }

  CachedPensCompanion toCompanion(bool nullToAbsent) {
    return CachedPensCompanion(
      id: Value(id),
      buildingId: Value(buildingId),
      code: Value(code),
      name: Value(name),
      enabled: Value(enabled),
      syncVersion: Value(syncVersion),
    );
  }

  factory CachedPen.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPen(
      id: serializer.fromJson<String>(json['id']),
      buildingId: serializer.fromJson<String>(json['buildingId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      syncVersion: serializer.fromJson<int>(json['syncVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'buildingId': serializer.toJson<String>(buildingId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'enabled': serializer.toJson<bool>(enabled),
      'syncVersion': serializer.toJson<int>(syncVersion),
    };
  }

  CachedPen copyWith(
          {String? id,
          String? buildingId,
          String? code,
          String? name,
          bool? enabled,
          int? syncVersion}) =>
      CachedPen(
        id: id ?? this.id,
        buildingId: buildingId ?? this.buildingId,
        code: code ?? this.code,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        syncVersion: syncVersion ?? this.syncVersion,
      );
  CachedPen copyWithCompanion(CachedPensCompanion data) {
    return CachedPen(
      id: data.id.present ? data.id.value : this.id,
      buildingId:
          data.buildingId.present ? data.buildingId.value : this.buildingId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      syncVersion:
          data.syncVersion.present ? data.syncVersion.value : this.syncVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPen(')
          ..write('id: $id, ')
          ..write('buildingId: $buildingId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('syncVersion: $syncVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, buildingId, code, name, enabled, syncVersion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPen &&
          other.id == this.id &&
          other.buildingId == this.buildingId &&
          other.code == this.code &&
          other.name == this.name &&
          other.enabled == this.enabled &&
          other.syncVersion == this.syncVersion);
}

class CachedPensCompanion extends UpdateCompanion<CachedPen> {
  final Value<String> id;
  final Value<String> buildingId;
  final Value<String> code;
  final Value<String> name;
  final Value<bool> enabled;
  final Value<int> syncVersion;
  final Value<int> rowid;
  const CachedPensCompanion({
    this.id = const Value.absent(),
    this.buildingId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.enabled = const Value.absent(),
    this.syncVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPensCompanion.insert({
    required String id,
    required String buildingId,
    required String code,
    required String name,
    this.enabled = const Value.absent(),
    this.syncVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        buildingId = Value(buildingId),
        code = Value(code),
        name = Value(name);
  static Insertable<CachedPen> custom({
    Expression<String>? id,
    Expression<String>? buildingId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<bool>? enabled,
    Expression<int>? syncVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (buildingId != null) 'building_id': buildingId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (enabled != null) 'enabled': enabled,
      if (syncVersion != null) 'sync_version': syncVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPensCompanion copyWith(
      {Value<String>? id,
      Value<String>? buildingId,
      Value<String>? code,
      Value<String>? name,
      Value<bool>? enabled,
      Value<int>? syncVersion,
      Value<int>? rowid}) {
    return CachedPensCompanion(
      id: id ?? this.id,
      buildingId: buildingId ?? this.buildingId,
      code: code ?? this.code,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      syncVersion: syncVersion ?? this.syncVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (buildingId.present) {
      map['building_id'] = Variable<String>(buildingId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (syncVersion.present) {
      map['sync_version'] = Variable<int>(syncVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPensCompanion(')
          ..write('id: $id, ')
          ..write('buildingId: $buildingId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('syncVersion: $syncVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta =
      const VerificationMeta('organizationId');
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
      'organization_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
      'cursor', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [organizationId, cursor, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(Insertable<SyncCursor> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
          _organizationIdMeta,
          organizationId.isAcceptableOrUnknown(
              data['organization_id']!, _organizationIdMeta));
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(_cursorMeta,
          cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta));
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId};
  @override
  SyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursor(
      organizationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}organization_id'])!,
      cursor: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cursor'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at'])!,
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursor extends DataClass implements Insertable<SyncCursor> {
  final String organizationId;
  final String cursor;
  final DateTime syncedAt;
  const SyncCursor(
      {required this.organizationId,
      required this.cursor,
      required this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['cursor'] = Variable<String>(cursor);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      organizationId: Value(organizationId),
      cursor: Value(cursor),
      syncedAt: Value(syncedAt),
    );
  }

  factory SyncCursor.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursor(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      cursor: serializer.fromJson<String>(json['cursor']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'cursor': serializer.toJson<String>(cursor),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
    };
  }

  SyncCursor copyWith(
          {String? organizationId, String? cursor, DateTime? syncedAt}) =>
      SyncCursor(
        organizationId: organizationId ?? this.organizationId,
        cursor: cursor ?? this.cursor,
        syncedAt: syncedAt ?? this.syncedAt,
      );
  SyncCursor copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursor(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursor(')
          ..write('organizationId: $organizationId, ')
          ..write('cursor: $cursor, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(organizationId, cursor, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursor &&
          other.organizationId == this.organizationId &&
          other.cursor == this.cursor &&
          other.syncedAt == this.syncedAt);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursor> {
  final Value<String> organizationId;
  final Value<String> cursor;
  final Value<DateTime> syncedAt;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.organizationId = const Value.absent(),
    this.cursor = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String organizationId,
    required String cursor,
    required DateTime syncedAt,
    this.rowid = const Value.absent(),
  })  : organizationId = Value(organizationId),
        cursor = Value(cursor),
        syncedAt = Value(syncedAt);
  static Insertable<SyncCursor> custom({
    Expression<String>? organizationId,
    Expression<String>? cursor,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (cursor != null) 'cursor': cursor,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith(
      {Value<String>? organizationId,
      Value<String>? cursor,
      Value<DateTime>? syncedAt,
      Value<int>? rowid}) {
    return SyncCursorsCompanion(
      organizationId: organizationId ?? this.organizationId,
      cursor: cursor ?? this.cursor,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('cursor: $cursor, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CaptureDraftsTable extends CaptureDrafts
    with TableInfo<$CaptureDraftsTable, CaptureDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CaptureDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _organizationIdMeta =
      const VerificationMeta('organizationId');
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
      'organization_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _penIdMeta = const VerificationMeta('penId');
  @override
  late final GeneratedColumn<String> penId = GeneratedColumn<String>(
      'pen_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _captureKindMeta =
      const VerificationMeta('captureKind');
  @override
  late final GeneratedColumn<String> captureKind = GeneratedColumn<String>(
      'capture_kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('draft'));
  static const VerificationMeta _businessDateMeta =
      const VerificationMeta('businessDate');
  @override
  late final GeneratedColumn<DateTime> businessDate = GeneratedColumn<DateTime>(
      'business_date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        organizationId,
        penId,
        captureKind,
        state,
        businessDate,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'capture_drafts';
  @override
  VerificationContext validateIntegrity(Insertable<CaptureDraft> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
          _organizationIdMeta,
          organizationId.isAcceptableOrUnknown(
              data['organization_id']!, _organizationIdMeta));
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('pen_id')) {
      context.handle(
          _penIdMeta, penId.isAcceptableOrUnknown(data['pen_id']!, _penIdMeta));
    } else if (isInserting) {
      context.missing(_penIdMeta);
    }
    if (data.containsKey('capture_kind')) {
      context.handle(
          _captureKindMeta,
          captureKind.isAcceptableOrUnknown(
              data['capture_kind']!, _captureKindMeta));
    } else if (isInserting) {
      context.missing(_captureKindMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    }
    if (data.containsKey('business_date')) {
      context.handle(
          _businessDateMeta,
          businessDate.isAcceptableOrUnknown(
              data['business_date']!, _businessDateMeta));
    } else if (isInserting) {
      context.missing(_businessDateMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CaptureDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CaptureDraft(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      organizationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}organization_id'])!,
      penId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pen_id'])!,
      captureKind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}capture_kind'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      businessDate: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}business_date'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CaptureDraftsTable createAlias(String alias) {
    return $CaptureDraftsTable(attachedDatabase, alias);
  }
}

class CaptureDraft extends DataClass implements Insertable<CaptureDraft> {
  final String id;
  final String organizationId;
  final String penId;
  final String captureKind;
  final String state;
  final DateTime businessDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CaptureDraft(
      {required this.id,
      required this.organizationId,
      required this.penId,
      required this.captureKind,
      required this.state,
      required this.businessDate,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['pen_id'] = Variable<String>(penId);
    map['capture_kind'] = Variable<String>(captureKind);
    map['state'] = Variable<String>(state);
    map['business_date'] = Variable<DateTime>(businessDate);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CaptureDraftsCompanion toCompanion(bool nullToAbsent) {
    return CaptureDraftsCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      penId: Value(penId),
      captureKind: Value(captureKind),
      state: Value(state),
      businessDate: Value(businessDate),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CaptureDraft.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CaptureDraft(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      penId: serializer.fromJson<String>(json['penId']),
      captureKind: serializer.fromJson<String>(json['captureKind']),
      state: serializer.fromJson<String>(json['state']),
      businessDate: serializer.fromJson<DateTime>(json['businessDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'penId': serializer.toJson<String>(penId),
      'captureKind': serializer.toJson<String>(captureKind),
      'state': serializer.toJson<String>(state),
      'businessDate': serializer.toJson<DateTime>(businessDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CaptureDraft copyWith(
          {String? id,
          String? organizationId,
          String? penId,
          String? captureKind,
          String? state,
          DateTime? businessDate,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      CaptureDraft(
        id: id ?? this.id,
        organizationId: organizationId ?? this.organizationId,
        penId: penId ?? this.penId,
        captureKind: captureKind ?? this.captureKind,
        state: state ?? this.state,
        businessDate: businessDate ?? this.businessDate,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CaptureDraft copyWithCompanion(CaptureDraftsCompanion data) {
    return CaptureDraft(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      penId: data.penId.present ? data.penId.value : this.penId,
      captureKind:
          data.captureKind.present ? data.captureKind.value : this.captureKind,
      state: data.state.present ? data.state.value : this.state,
      businessDate: data.businessDate.present
          ? data.businessDate.value
          : this.businessDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CaptureDraft(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('penId: $penId, ')
          ..write('captureKind: $captureKind, ')
          ..write('state: $state, ')
          ..write('businessDate: $businessDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, organizationId, penId, captureKind, state,
      businessDate, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CaptureDraft &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.penId == this.penId &&
          other.captureKind == this.captureKind &&
          other.state == this.state &&
          other.businessDate == this.businessDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CaptureDraftsCompanion extends UpdateCompanion<CaptureDraft> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> penId;
  final Value<String> captureKind;
  final Value<String> state;
  final Value<DateTime> businessDate;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CaptureDraftsCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.penId = const Value.absent(),
    this.captureKind = const Value.absent(),
    this.state = const Value.absent(),
    this.businessDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CaptureDraftsCompanion.insert({
    required String id,
    required String organizationId,
    required String penId,
    required String captureKind,
    this.state = const Value.absent(),
    required DateTime businessDate,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        organizationId = Value(organizationId),
        penId = Value(penId),
        captureKind = Value(captureKind),
        businessDate = Value(businessDate),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<CaptureDraft> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? penId,
    Expression<String>? captureKind,
    Expression<String>? state,
    Expression<DateTime>? businessDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (penId != null) 'pen_id': penId,
      if (captureKind != null) 'capture_kind': captureKind,
      if (state != null) 'state': state,
      if (businessDate != null) 'business_date': businessDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CaptureDraftsCompanion copyWith(
      {Value<String>? id,
      Value<String>? organizationId,
      Value<String>? penId,
      Value<String>? captureKind,
      Value<String>? state,
      Value<DateTime>? businessDate,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CaptureDraftsCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      penId: penId ?? this.penId,
      captureKind: captureKind ?? this.captureKind,
      state: state ?? this.state,
      businessDate: businessDate ?? this.businessDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (penId.present) {
      map['pen_id'] = Variable<String>(penId.value);
    }
    if (captureKind.present) {
      map['capture_kind'] = Variable<String>(captureKind.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (businessDate.present) {
      map['business_date'] = Variable<DateTime>(businessDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CaptureDraftsCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('penId: $penId, ')
          ..write('captureKind: $captureKind, ')
          ..write('state: $state, ')
          ..write('businessDate: $businessDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CaptureSetsTable extends CaptureSets
    with TableInfo<$CaptureSetsTable, CaptureSet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CaptureSetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _draftIdMeta =
      const VerificationMeta('draftId');
  @override
  late final GeneratedColumn<String> draftId = GeneratedColumn<String>(
      'draft_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, draftId, kind, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'capture_sets';
  @override
  VerificationContext validateIntegrity(Insertable<CaptureSet> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('draft_id')) {
      context.handle(_draftIdMeta,
          draftId.isAcceptableOrUnknown(data['draft_id']!, _draftIdMeta));
    } else if (isInserting) {
      context.missing(_draftIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CaptureSet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CaptureSet(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      draftId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}draft_id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $CaptureSetsTable createAlias(String alias) {
    return $CaptureSetsTable(attachedDatabase, alias);
  }
}

class CaptureSet extends DataClass implements Insertable<CaptureSet> {
  final String id;
  final String draftId;
  final String kind;
  final DateTime createdAt;
  const CaptureSet(
      {required this.id,
      required this.draftId,
      required this.kind,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['draft_id'] = Variable<String>(draftId);
    map['kind'] = Variable<String>(kind);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CaptureSetsCompanion toCompanion(bool nullToAbsent) {
    return CaptureSetsCompanion(
      id: Value(id),
      draftId: Value(draftId),
      kind: Value(kind),
      createdAt: Value(createdAt),
    );
  }

  factory CaptureSet.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CaptureSet(
      id: serializer.fromJson<String>(json['id']),
      draftId: serializer.fromJson<String>(json['draftId']),
      kind: serializer.fromJson<String>(json['kind']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'draftId': serializer.toJson<String>(draftId),
      'kind': serializer.toJson<String>(kind),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CaptureSet copyWith(
          {String? id, String? draftId, String? kind, DateTime? createdAt}) =>
      CaptureSet(
        id: id ?? this.id,
        draftId: draftId ?? this.draftId,
        kind: kind ?? this.kind,
        createdAt: createdAt ?? this.createdAt,
      );
  CaptureSet copyWithCompanion(CaptureSetsCompanion data) {
    return CaptureSet(
      id: data.id.present ? data.id.value : this.id,
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
      kind: data.kind.present ? data.kind.value : this.kind,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CaptureSet(')
          ..write('id: $id, ')
          ..write('draftId: $draftId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, draftId, kind, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CaptureSet &&
          other.id == this.id &&
          other.draftId == this.draftId &&
          other.kind == this.kind &&
          other.createdAt == this.createdAt);
}

class CaptureSetsCompanion extends UpdateCompanion<CaptureSet> {
  final Value<String> id;
  final Value<String> draftId;
  final Value<String> kind;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CaptureSetsCompanion({
    this.id = const Value.absent(),
    this.draftId = const Value.absent(),
    this.kind = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CaptureSetsCompanion.insert({
    required String id,
    required String draftId,
    required String kind,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        draftId = Value(draftId),
        kind = Value(kind),
        createdAt = Value(createdAt);
  static Insertable<CaptureSet> custom({
    Expression<String>? id,
    Expression<String>? draftId,
    Expression<String>? kind,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (draftId != null) 'draft_id': draftId,
      if (kind != null) 'kind': kind,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CaptureSetsCompanion copyWith(
      {Value<String>? id,
      Value<String>? draftId,
      Value<String>? kind,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return CaptureSetsCompanion(
      id: id ?? this.id,
      draftId: draftId ?? this.draftId,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CaptureSetsCompanion(')
          ..write('id: $id, ')
          ..write('draftId: $draftId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalMediaAssetsTable extends LocalMediaAssets
    with TableInfo<$LocalMediaAssetsTable, LocalMediaAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMediaAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _draftIdMeta =
      const VerificationMeta('draftId');
  @override
  late final GeneratedColumn<String> draftId = GeneratedColumn<String>(
      'draft_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _viewPositionMeta =
      const VerificationMeta('viewPosition');
  @override
  late final GeneratedColumn<String> viewPosition = GeneratedColumn<String>(
      'view_position', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _materializedPathMeta =
      const VerificationMeta('materializedPath');
  @override
  late final GeneratedColumn<String> materializedPath = GeneratedColumn<String>(
      'materialized_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _originalNameMeta =
      const VerificationMeta('originalName');
  @override
  late final GeneratedColumn<String> originalName = GeneratedColumn<String>(
      'original_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentTypeMeta =
      const VerificationMeta('contentType');
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
      'content_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _byteSizeMeta =
      const VerificationMeta('byteSize');
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
      'byte_size', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
      'sha256', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roiJsonMeta =
      const VerificationMeta('roiJson');
  @override
  late final GeneratedColumn<String> roiJson = GeneratedColumn<String>(
      'roi_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _exifJsonMeta =
      const VerificationMeta('exifJson');
  @override
  late final GeneratedColumn<String> exifJson = GeneratedColumn<String>(
      'exif_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _capturedAtMeta =
      const VerificationMeta('capturedAt');
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
      'captured_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
      'width', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
      'height', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        draftId,
        viewPosition,
        materializedPath,
        originalName,
        contentType,
        byteSize,
        sha256,
        roiJson,
        exifJson,
        capturedAt,
        width,
        height,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_media_assets';
  @override
  VerificationContext validateIntegrity(Insertable<LocalMediaAsset> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('draft_id')) {
      context.handle(_draftIdMeta,
          draftId.isAcceptableOrUnknown(data['draft_id']!, _draftIdMeta));
    } else if (isInserting) {
      context.missing(_draftIdMeta);
    }
    if (data.containsKey('view_position')) {
      context.handle(
          _viewPositionMeta,
          viewPosition.isAcceptableOrUnknown(
              data['view_position']!, _viewPositionMeta));
    } else if (isInserting) {
      context.missing(_viewPositionMeta);
    }
    if (data.containsKey('materialized_path')) {
      context.handle(
          _materializedPathMeta,
          materializedPath.isAcceptableOrUnknown(
              data['materialized_path']!, _materializedPathMeta));
    } else if (isInserting) {
      context.missing(_materializedPathMeta);
    }
    if (data.containsKey('original_name')) {
      context.handle(
          _originalNameMeta,
          originalName.isAcceptableOrUnknown(
              data['original_name']!, _originalNameMeta));
    } else if (isInserting) {
      context.missing(_originalNameMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
          _contentTypeMeta,
          contentType.isAcceptableOrUnknown(
              data['content_type']!, _contentTypeMeta));
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(_byteSizeMeta,
          byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta));
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(_sha256Meta,
          sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta));
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('roi_json')) {
      context.handle(_roiJsonMeta,
          roiJson.isAcceptableOrUnknown(data['roi_json']!, _roiJsonMeta));
    }
    if (data.containsKey('exif_json')) {
      context.handle(_exifJsonMeta,
          exifJson.isAcceptableOrUnknown(data['exif_json']!, _exifJsonMeta));
    }
    if (data.containsKey('captured_at')) {
      context.handle(
          _capturedAtMeta,
          capturedAt.isAcceptableOrUnknown(
              data['captured_at']!, _capturedAtMeta));
    }
    if (data.containsKey('width')) {
      context.handle(
          _widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    }
    if (data.containsKey('height')) {
      context.handle(_heightMeta,
          height.isAcceptableOrUnknown(data['height']!, _heightMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {draftId, viewPosition},
      ];
  @override
  LocalMediaAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMediaAsset(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      draftId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}draft_id'])!,
      viewPosition: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}view_position'])!,
      materializedPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}materialized_path'])!,
      originalName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}original_name'])!,
      contentType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_type'])!,
      byteSize: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}byte_size'])!,
      sha256: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sha256'])!,
      roiJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}roi_json'])!,
      exifJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}exif_json'])!,
      capturedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}captured_at']),
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}width']),
      height: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}height']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $LocalMediaAssetsTable createAlias(String alias) {
    return $LocalMediaAssetsTable(attachedDatabase, alias);
  }
}

class LocalMediaAsset extends DataClass implements Insertable<LocalMediaAsset> {
  final String id;
  final String draftId;
  final String viewPosition;
  final String materializedPath;
  final String originalName;
  final String contentType;
  final int byteSize;
  final String sha256;
  final String roiJson;
  final String exifJson;
  final DateTime? capturedAt;
  final int? width;
  final int? height;
  final DateTime createdAt;
  const LocalMediaAsset(
      {required this.id,
      required this.draftId,
      required this.viewPosition,
      required this.materializedPath,
      required this.originalName,
      required this.contentType,
      required this.byteSize,
      required this.sha256,
      required this.roiJson,
      required this.exifJson,
      this.capturedAt,
      this.width,
      this.height,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['draft_id'] = Variable<String>(draftId);
    map['view_position'] = Variable<String>(viewPosition);
    map['materialized_path'] = Variable<String>(materializedPath);
    map['original_name'] = Variable<String>(originalName);
    map['content_type'] = Variable<String>(contentType);
    map['byte_size'] = Variable<int>(byteSize);
    map['sha256'] = Variable<String>(sha256);
    map['roi_json'] = Variable<String>(roiJson);
    map['exif_json'] = Variable<String>(exifJson);
    if (!nullToAbsent || capturedAt != null) {
      map['captured_at'] = Variable<DateTime>(capturedAt);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LocalMediaAssetsCompanion toCompanion(bool nullToAbsent) {
    return LocalMediaAssetsCompanion(
      id: Value(id),
      draftId: Value(draftId),
      viewPosition: Value(viewPosition),
      materializedPath: Value(materializedPath),
      originalName: Value(originalName),
      contentType: Value(contentType),
      byteSize: Value(byteSize),
      sha256: Value(sha256),
      roiJson: Value(roiJson),
      exifJson: Value(exifJson),
      capturedAt: capturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(capturedAt),
      width:
          width == null && nullToAbsent ? const Value.absent() : Value(width),
      height:
          height == null && nullToAbsent ? const Value.absent() : Value(height),
      createdAt: Value(createdAt),
    );
  }

  factory LocalMediaAsset.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMediaAsset(
      id: serializer.fromJson<String>(json['id']),
      draftId: serializer.fromJson<String>(json['draftId']),
      viewPosition: serializer.fromJson<String>(json['viewPosition']),
      materializedPath: serializer.fromJson<String>(json['materializedPath']),
      originalName: serializer.fromJson<String>(json['originalName']),
      contentType: serializer.fromJson<String>(json['contentType']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      sha256: serializer.fromJson<String>(json['sha256']),
      roiJson: serializer.fromJson<String>(json['roiJson']),
      exifJson: serializer.fromJson<String>(json['exifJson']),
      capturedAt: serializer.fromJson<DateTime?>(json['capturedAt']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'draftId': serializer.toJson<String>(draftId),
      'viewPosition': serializer.toJson<String>(viewPosition),
      'materializedPath': serializer.toJson<String>(materializedPath),
      'originalName': serializer.toJson<String>(originalName),
      'contentType': serializer.toJson<String>(contentType),
      'byteSize': serializer.toJson<int>(byteSize),
      'sha256': serializer.toJson<String>(sha256),
      'roiJson': serializer.toJson<String>(roiJson),
      'exifJson': serializer.toJson<String>(exifJson),
      'capturedAt': serializer.toJson<DateTime?>(capturedAt),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LocalMediaAsset copyWith(
          {String? id,
          String? draftId,
          String? viewPosition,
          String? materializedPath,
          String? originalName,
          String? contentType,
          int? byteSize,
          String? sha256,
          String? roiJson,
          String? exifJson,
          Value<DateTime?> capturedAt = const Value.absent(),
          Value<int?> width = const Value.absent(),
          Value<int?> height = const Value.absent(),
          DateTime? createdAt}) =>
      LocalMediaAsset(
        id: id ?? this.id,
        draftId: draftId ?? this.draftId,
        viewPosition: viewPosition ?? this.viewPosition,
        materializedPath: materializedPath ?? this.materializedPath,
        originalName: originalName ?? this.originalName,
        contentType: contentType ?? this.contentType,
        byteSize: byteSize ?? this.byteSize,
        sha256: sha256 ?? this.sha256,
        roiJson: roiJson ?? this.roiJson,
        exifJson: exifJson ?? this.exifJson,
        capturedAt: capturedAt.present ? capturedAt.value : this.capturedAt,
        width: width.present ? width.value : this.width,
        height: height.present ? height.value : this.height,
        createdAt: createdAt ?? this.createdAt,
      );
  LocalMediaAsset copyWithCompanion(LocalMediaAssetsCompanion data) {
    return LocalMediaAsset(
      id: data.id.present ? data.id.value : this.id,
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
      viewPosition: data.viewPosition.present
          ? data.viewPosition.value
          : this.viewPosition,
      materializedPath: data.materializedPath.present
          ? data.materializedPath.value
          : this.materializedPath,
      originalName: data.originalName.present
          ? data.originalName.value
          : this.originalName,
      contentType:
          data.contentType.present ? data.contentType.value : this.contentType,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      roiJson: data.roiJson.present ? data.roiJson.value : this.roiJson,
      exifJson: data.exifJson.present ? data.exifJson.value : this.exifJson,
      capturedAt:
          data.capturedAt.present ? data.capturedAt.value : this.capturedAt,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMediaAsset(')
          ..write('id: $id, ')
          ..write('draftId: $draftId, ')
          ..write('viewPosition: $viewPosition, ')
          ..write('materializedPath: $materializedPath, ')
          ..write('originalName: $originalName, ')
          ..write('contentType: $contentType, ')
          ..write('byteSize: $byteSize, ')
          ..write('sha256: $sha256, ')
          ..write('roiJson: $roiJson, ')
          ..write('exifJson: $exifJson, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      draftId,
      viewPosition,
      materializedPath,
      originalName,
      contentType,
      byteSize,
      sha256,
      roiJson,
      exifJson,
      capturedAt,
      width,
      height,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMediaAsset &&
          other.id == this.id &&
          other.draftId == this.draftId &&
          other.viewPosition == this.viewPosition &&
          other.materializedPath == this.materializedPath &&
          other.originalName == this.originalName &&
          other.contentType == this.contentType &&
          other.byteSize == this.byteSize &&
          other.sha256 == this.sha256 &&
          other.roiJson == this.roiJson &&
          other.exifJson == this.exifJson &&
          other.capturedAt == this.capturedAt &&
          other.width == this.width &&
          other.height == this.height &&
          other.createdAt == this.createdAt);
}

class LocalMediaAssetsCompanion extends UpdateCompanion<LocalMediaAsset> {
  final Value<String> id;
  final Value<String> draftId;
  final Value<String> viewPosition;
  final Value<String> materializedPath;
  final Value<String> originalName;
  final Value<String> contentType;
  final Value<int> byteSize;
  final Value<String> sha256;
  final Value<String> roiJson;
  final Value<String> exifJson;
  final Value<DateTime?> capturedAt;
  final Value<int?> width;
  final Value<int?> height;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalMediaAssetsCompanion({
    this.id = const Value.absent(),
    this.draftId = const Value.absent(),
    this.viewPosition = const Value.absent(),
    this.materializedPath = const Value.absent(),
    this.originalName = const Value.absent(),
    this.contentType = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.roiJson = const Value.absent(),
    this.exifJson = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMediaAssetsCompanion.insert({
    required String id,
    required String draftId,
    required String viewPosition,
    required String materializedPath,
    required String originalName,
    required String contentType,
    required int byteSize,
    required String sha256,
    this.roiJson = const Value.absent(),
    this.exifJson = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        draftId = Value(draftId),
        viewPosition = Value(viewPosition),
        materializedPath = Value(materializedPath),
        originalName = Value(originalName),
        contentType = Value(contentType),
        byteSize = Value(byteSize),
        sha256 = Value(sha256),
        createdAt = Value(createdAt);
  static Insertable<LocalMediaAsset> custom({
    Expression<String>? id,
    Expression<String>? draftId,
    Expression<String>? viewPosition,
    Expression<String>? materializedPath,
    Expression<String>? originalName,
    Expression<String>? contentType,
    Expression<int>? byteSize,
    Expression<String>? sha256,
    Expression<String>? roiJson,
    Expression<String>? exifJson,
    Expression<DateTime>? capturedAt,
    Expression<int>? width,
    Expression<int>? height,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (draftId != null) 'draft_id': draftId,
      if (viewPosition != null) 'view_position': viewPosition,
      if (materializedPath != null) 'materialized_path': materializedPath,
      if (originalName != null) 'original_name': originalName,
      if (contentType != null) 'content_type': contentType,
      if (byteSize != null) 'byte_size': byteSize,
      if (sha256 != null) 'sha256': sha256,
      if (roiJson != null) 'roi_json': roiJson,
      if (exifJson != null) 'exif_json': exifJson,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMediaAssetsCompanion copyWith(
      {Value<String>? id,
      Value<String>? draftId,
      Value<String>? viewPosition,
      Value<String>? materializedPath,
      Value<String>? originalName,
      Value<String>? contentType,
      Value<int>? byteSize,
      Value<String>? sha256,
      Value<String>? roiJson,
      Value<String>? exifJson,
      Value<DateTime?>? capturedAt,
      Value<int?>? width,
      Value<int?>? height,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return LocalMediaAssetsCompanion(
      id: id ?? this.id,
      draftId: draftId ?? this.draftId,
      viewPosition: viewPosition ?? this.viewPosition,
      materializedPath: materializedPath ?? this.materializedPath,
      originalName: originalName ?? this.originalName,
      contentType: contentType ?? this.contentType,
      byteSize: byteSize ?? this.byteSize,
      sha256: sha256 ?? this.sha256,
      roiJson: roiJson ?? this.roiJson,
      exifJson: exifJson ?? this.exifJson,
      capturedAt: capturedAt ?? this.capturedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
    }
    if (viewPosition.present) {
      map['view_position'] = Variable<String>(viewPosition.value);
    }
    if (materializedPath.present) {
      map['materialized_path'] = Variable<String>(materializedPath.value);
    }
    if (originalName.present) {
      map['original_name'] = Variable<String>(originalName.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (roiJson.present) {
      map['roi_json'] = Variable<String>(roiJson.value);
    }
    if (exifJson.present) {
      map['exif_json'] = Variable<String>(exifJson.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMediaAssetsCompanion(')
          ..write('id: $id, ')
          ..write('draftId: $draftId, ')
          ..write('viewPosition: $viewPosition, ')
          ..write('materializedPath: $materializedPath, ')
          ..write('originalName: $originalName, ')
          ..write('contentType: $contentType, ')
          ..write('byteSize: $byteSize, ')
          ..write('sha256: $sha256, ')
          ..write('roiJson: $roiJson, ')
          ..write('exifJson: $exifJson, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxEntriesTable extends OutboxEntries
    with TableInfo<$OutboxEntriesTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packageIdMeta =
      const VerificationMeta('packageId');
  @override
  late final GeneratedColumn<String> packageId = GeneratedColumn<String>(
      'package_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _draftIdMeta =
      const VerificationMeta('draftId');
  @override
  late final GeneratedColumn<String> draftId = GeneratedColumn<String>(
      'draft_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _idempotencyKeyMeta =
      const VerificationMeta('idempotencyKey');
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
      'idempotency_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('queued'));
  static const VerificationMeta _manifestJsonMeta =
      const VerificationMeta('manifestJson');
  @override
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
      'manifest_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
      'error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serverPackageIdMeta =
      const VerificationMeta('serverPackageId');
  @override
  late final GeneratedColumn<String> serverPackageId = GeneratedColumn<String>(
      'server_package_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
      'session_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _inferenceJobIdMeta =
      const VerificationMeta('inferenceJobId');
  @override
  late final GeneratedColumn<String> inferenceJobId = GeneratedColumn<String>(
      'inference_job_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _attemptCountMeta =
      const VerificationMeta('attemptCount');
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
      'attempt_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _nextAttemptAtMeta =
      const VerificationMeta('nextAttemptAt');
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>('next_attempt_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _leaseOwnerMeta =
      const VerificationMeta('leaseOwner');
  @override
  late final GeneratedColumn<String> leaseOwner = GeneratedColumn<String>(
      'lease_owner', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _leaseExpiresAtMeta =
      const VerificationMeta('leaseExpiresAt');
  @override
  late final GeneratedColumn<DateTime> leaseExpiresAt =
      GeneratedColumn<DateTime>('lease_expires_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        packageId,
        draftId,
        idempotencyKey,
        state,
        manifestJson,
        error,
        serverPackageId,
        sessionId,
        inferenceJobId,
        attemptCount,
        nextAttemptAt,
        leaseOwner,
        leaseExpiresAt,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_entries';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('package_id')) {
      context.handle(_packageIdMeta,
          packageId.isAcceptableOrUnknown(data['package_id']!, _packageIdMeta));
    } else if (isInserting) {
      context.missing(_packageIdMeta);
    }
    if (data.containsKey('draft_id')) {
      context.handle(_draftIdMeta,
          draftId.isAcceptableOrUnknown(data['draft_id']!, _draftIdMeta));
    } else if (isInserting) {
      context.missing(_draftIdMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
          _idempotencyKeyMeta,
          idempotencyKey.isAcceptableOrUnknown(
              data['idempotency_key']!, _idempotencyKeyMeta));
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    }
    if (data.containsKey('manifest_json')) {
      context.handle(
          _manifestJsonMeta,
          manifestJson.isAcceptableOrUnknown(
              data['manifest_json']!, _manifestJsonMeta));
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('error')) {
      context.handle(
          _errorMeta, error.isAcceptableOrUnknown(data['error']!, _errorMeta));
    }
    if (data.containsKey('server_package_id')) {
      context.handle(
          _serverPackageIdMeta,
          serverPackageId.isAcceptableOrUnknown(
              data['server_package_id']!, _serverPackageIdMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    }
    if (data.containsKey('inference_job_id')) {
      context.handle(
          _inferenceJobIdMeta,
          inferenceJobId.isAcceptableOrUnknown(
              data['inference_job_id']!, _inferenceJobIdMeta));
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
          _attemptCountMeta,
          attemptCount.isAcceptableOrUnknown(
              data['attempt_count']!, _attemptCountMeta));
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
          _nextAttemptAtMeta,
          nextAttemptAt.isAcceptableOrUnknown(
              data['next_attempt_at']!, _nextAttemptAtMeta));
    }
    if (data.containsKey('lease_owner')) {
      context.handle(
          _leaseOwnerMeta,
          leaseOwner.isAcceptableOrUnknown(
              data['lease_owner']!, _leaseOwnerMeta));
    }
    if (data.containsKey('lease_expires_at')) {
      context.handle(
          _leaseExpiresAtMeta,
          leaseExpiresAt.isAcceptableOrUnknown(
              data['lease_expires_at']!, _leaseExpiresAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packageId};
  @override
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
      packageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_id'])!,
      draftId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}draft_id'])!,
      idempotencyKey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}idempotency_key'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      manifestJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}manifest_json'])!,
      error: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error']),
      serverPackageId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}server_package_id']),
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_id']),
      inferenceJobId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}inference_job_id']),
      attemptCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempt_count'])!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}next_attempt_at']),
      leaseOwner: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}lease_owner']),
      leaseExpiresAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}lease_expires_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $OutboxEntriesTable createAlias(String alias) {
    return $OutboxEntriesTable(attachedDatabase, alias);
  }
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  final String packageId;
  final String draftId;
  final String idempotencyKey;
  final String state;
  final String manifestJson;
  final String? error;
  final String? serverPackageId;
  final String? sessionId;
  final String? inferenceJobId;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? leaseOwner;
  final DateTime? leaseExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const OutboxEntry(
      {required this.packageId,
      required this.draftId,
      required this.idempotencyKey,
      required this.state,
      required this.manifestJson,
      this.error,
      this.serverPackageId,
      this.sessionId,
      this.inferenceJobId,
      required this.attemptCount,
      this.nextAttemptAt,
      this.leaseOwner,
      this.leaseExpiresAt,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['package_id'] = Variable<String>(packageId);
    map['draft_id'] = Variable<String>(draftId);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['state'] = Variable<String>(state);
    map['manifest_json'] = Variable<String>(manifestJson);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    if (!nullToAbsent || serverPackageId != null) {
      map['server_package_id'] = Variable<String>(serverPackageId);
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    if (!nullToAbsent || inferenceJobId != null) {
      map['inference_job_id'] = Variable<String>(inferenceJobId);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || leaseOwner != null) {
      map['lease_owner'] = Variable<String>(leaseOwner);
    }
    if (!nullToAbsent || leaseExpiresAt != null) {
      map['lease_expires_at'] = Variable<DateTime>(leaseExpiresAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboxEntriesCompanion(
      packageId: Value(packageId),
      draftId: Value(draftId),
      idempotencyKey: Value(idempotencyKey),
      state: Value(state),
      manifestJson: Value(manifestJson),
      error:
          error == null && nullToAbsent ? const Value.absent() : Value(error),
      serverPackageId: serverPackageId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverPackageId),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      inferenceJobId: inferenceJobId == null && nullToAbsent
          ? const Value.absent()
          : Value(inferenceJobId),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      leaseOwner: leaseOwner == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseOwner),
      leaseExpiresAt: leaseExpiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseExpiresAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory OutboxEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
      packageId: serializer.fromJson<String>(json['packageId']),
      draftId: serializer.fromJson<String>(json['draftId']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      state: serializer.fromJson<String>(json['state']),
      manifestJson: serializer.fromJson<String>(json['manifestJson']),
      error: serializer.fromJson<String?>(json['error']),
      serverPackageId: serializer.fromJson<String?>(json['serverPackageId']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      inferenceJobId: serializer.fromJson<String?>(json['inferenceJobId']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      leaseOwner: serializer.fromJson<String?>(json['leaseOwner']),
      leaseExpiresAt: serializer.fromJson<DateTime?>(json['leaseExpiresAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packageId': serializer.toJson<String>(packageId),
      'draftId': serializer.toJson<String>(draftId),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'state': serializer.toJson<String>(state),
      'manifestJson': serializer.toJson<String>(manifestJson),
      'error': serializer.toJson<String?>(error),
      'serverPackageId': serializer.toJson<String?>(serverPackageId),
      'sessionId': serializer.toJson<String?>(sessionId),
      'inferenceJobId': serializer.toJson<String?>(inferenceJobId),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'leaseOwner': serializer.toJson<String?>(leaseOwner),
      'leaseExpiresAt': serializer.toJson<DateTime?>(leaseExpiresAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  OutboxEntry copyWith(
          {String? packageId,
          String? draftId,
          String? idempotencyKey,
          String? state,
          String? manifestJson,
          Value<String?> error = const Value.absent(),
          Value<String?> serverPackageId = const Value.absent(),
          Value<String?> sessionId = const Value.absent(),
          Value<String?> inferenceJobId = const Value.absent(),
          int? attemptCount,
          Value<DateTime?> nextAttemptAt = const Value.absent(),
          Value<String?> leaseOwner = const Value.absent(),
          Value<DateTime?> leaseExpiresAt = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      OutboxEntry(
        packageId: packageId ?? this.packageId,
        draftId: draftId ?? this.draftId,
        idempotencyKey: idempotencyKey ?? this.idempotencyKey,
        state: state ?? this.state,
        manifestJson: manifestJson ?? this.manifestJson,
        error: error.present ? error.value : this.error,
        serverPackageId: serverPackageId.present
            ? serverPackageId.value
            : this.serverPackageId,
        sessionId: sessionId.present ? sessionId.value : this.sessionId,
        inferenceJobId:
            inferenceJobId.present ? inferenceJobId.value : this.inferenceJobId,
        attemptCount: attemptCount ?? this.attemptCount,
        nextAttemptAt:
            nextAttemptAt.present ? nextAttemptAt.value : this.nextAttemptAt,
        leaseOwner: leaseOwner.present ? leaseOwner.value : this.leaseOwner,
        leaseExpiresAt:
            leaseExpiresAt.present ? leaseExpiresAt.value : this.leaseExpiresAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  OutboxEntry copyWithCompanion(OutboxEntriesCompanion data) {
    return OutboxEntry(
      packageId: data.packageId.present ? data.packageId.value : this.packageId,
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      state: data.state.present ? data.state.value : this.state,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      error: data.error.present ? data.error.value : this.error,
      serverPackageId: data.serverPackageId.present
          ? data.serverPackageId.value
          : this.serverPackageId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      inferenceJobId: data.inferenceJobId.present
          ? data.inferenceJobId.value
          : this.inferenceJobId,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      leaseOwner:
          data.leaseOwner.present ? data.leaseOwner.value : this.leaseOwner,
      leaseExpiresAt: data.leaseExpiresAt.present
          ? data.leaseExpiresAt.value
          : this.leaseExpiresAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
          ..write('packageId: $packageId, ')
          ..write('draftId: $draftId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('state: $state, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('error: $error, ')
          ..write('serverPackageId: $serverPackageId, ')
          ..write('sessionId: $sessionId, ')
          ..write('inferenceJobId: $inferenceJobId, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseExpiresAt: $leaseExpiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      packageId,
      draftId,
      idempotencyKey,
      state,
      manifestJson,
      error,
      serverPackageId,
      sessionId,
      inferenceJobId,
      attemptCount,
      nextAttemptAt,
      leaseOwner,
      leaseExpiresAt,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntry &&
          other.packageId == this.packageId &&
          other.draftId == this.draftId &&
          other.idempotencyKey == this.idempotencyKey &&
          other.state == this.state &&
          other.manifestJson == this.manifestJson &&
          other.error == this.error &&
          other.serverPackageId == this.serverPackageId &&
          other.sessionId == this.sessionId &&
          other.inferenceJobId == this.inferenceJobId &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.leaseOwner == this.leaseOwner &&
          other.leaseExpiresAt == this.leaseExpiresAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OutboxEntriesCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<String> packageId;
  final Value<String> draftId;
  final Value<String> idempotencyKey;
  final Value<String> state;
  final Value<String> manifestJson;
  final Value<String?> error;
  final Value<String?> serverPackageId;
  final Value<String?> sessionId;
  final Value<String?> inferenceJobId;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> leaseOwner;
  final Value<DateTime?> leaseExpiresAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const OutboxEntriesCompanion({
    this.packageId = const Value.absent(),
    this.draftId = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.state = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.error = const Value.absent(),
    this.serverPackageId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.inferenceJobId = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.leaseOwner = const Value.absent(),
    this.leaseExpiresAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxEntriesCompanion.insert({
    required String packageId,
    required String draftId,
    required String idempotencyKey,
    this.state = const Value.absent(),
    required String manifestJson,
    this.error = const Value.absent(),
    this.serverPackageId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.inferenceJobId = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.leaseOwner = const Value.absent(),
    this.leaseExpiresAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : packageId = Value(packageId),
        draftId = Value(draftId),
        idempotencyKey = Value(idempotencyKey),
        manifestJson = Value(manifestJson),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<OutboxEntry> custom({
    Expression<String>? packageId,
    Expression<String>? draftId,
    Expression<String>? idempotencyKey,
    Expression<String>? state,
    Expression<String>? manifestJson,
    Expression<String>? error,
    Expression<String>? serverPackageId,
    Expression<String>? sessionId,
    Expression<String>? inferenceJobId,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? leaseOwner,
    Expression<DateTime>? leaseExpiresAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packageId != null) 'package_id': packageId,
      if (draftId != null) 'draft_id': draftId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (state != null) 'state': state,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (error != null) 'error': error,
      if (serverPackageId != null) 'server_package_id': serverPackageId,
      if (sessionId != null) 'session_id': sessionId,
      if (inferenceJobId != null) 'inference_job_id': inferenceJobId,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (leaseOwner != null) 'lease_owner': leaseOwner,
      if (leaseExpiresAt != null) 'lease_expires_at': leaseExpiresAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxEntriesCompanion copyWith(
      {Value<String>? packageId,
      Value<String>? draftId,
      Value<String>? idempotencyKey,
      Value<String>? state,
      Value<String>? manifestJson,
      Value<String?>? error,
      Value<String?>? serverPackageId,
      Value<String?>? sessionId,
      Value<String?>? inferenceJobId,
      Value<int>? attemptCount,
      Value<DateTime?>? nextAttemptAt,
      Value<String?>? leaseOwner,
      Value<DateTime?>? leaseExpiresAt,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return OutboxEntriesCompanion(
      packageId: packageId ?? this.packageId,
      draftId: draftId ?? this.draftId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      state: state ?? this.state,
      manifestJson: manifestJson ?? this.manifestJson,
      error: error ?? this.error,
      serverPackageId: serverPackageId ?? this.serverPackageId,
      sessionId: sessionId ?? this.sessionId,
      inferenceJobId: inferenceJobId ?? this.inferenceJobId,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      leaseOwner: leaseOwner ?? this.leaseOwner,
      leaseExpiresAt: leaseExpiresAt ?? this.leaseExpiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packageId.present) {
      map['package_id'] = Variable<String>(packageId.value);
    }
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (manifestJson.present) {
      map['manifest_json'] = Variable<String>(manifestJson.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (serverPackageId.present) {
      map['server_package_id'] = Variable<String>(serverPackageId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (inferenceJobId.present) {
      map['inference_job_id'] = Variable<String>(inferenceJobId.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (leaseOwner.present) {
      map['lease_owner'] = Variable<String>(leaseOwner.value);
    }
    if (leaseExpiresAt.present) {
      map['lease_expires_at'] = Variable<DateTime>(leaseExpiresAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntriesCompanion(')
          ..write('packageId: $packageId, ')
          ..write('draftId: $draftId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('state: $state, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('error: $error, ')
          ..write('serverPackageId: $serverPackageId, ')
          ..write('sessionId: $sessionId, ')
          ..write('inferenceJobId: $inferenceJobId, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseExpiresAt: $leaseExpiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadAssetEntriesTable extends UploadAssetEntries
    with TableInfo<$UploadAssetEntriesTable, UploadAssetEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadAssetEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packageIdMeta =
      const VerificationMeta('packageId');
  @override
  late final GeneratedColumn<String> packageId = GeneratedColumn<String>(
      'package_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _assetIdMeta =
      const VerificationMeta('assetId');
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
      'asset_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _attemptCountMeta =
      const VerificationMeta('attemptCount');
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
      'attempt_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _errorCodeMeta =
      const VerificationMeta('errorCode');
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
      'error_code', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _uploadedAtMeta =
      const VerificationMeta('uploadedAt');
  @override
  late final GeneratedColumn<DateTime> uploadedAt = GeneratedColumn<DateTime>(
      'uploaded_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        packageId,
        assetId,
        state,
        attemptCount,
        errorCode,
        uploadedAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_asset_entries';
  @override
  VerificationContext validateIntegrity(Insertable<UploadAssetEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('package_id')) {
      context.handle(_packageIdMeta,
          packageId.isAcceptableOrUnknown(data['package_id']!, _packageIdMeta));
    } else if (isInserting) {
      context.missing(_packageIdMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(_assetIdMeta,
          assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta));
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
          _attemptCountMeta,
          attemptCount.isAcceptableOrUnknown(
              data['attempt_count']!, _attemptCountMeta));
    }
    if (data.containsKey('error_code')) {
      context.handle(_errorCodeMeta,
          errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta));
    }
    if (data.containsKey('uploaded_at')) {
      context.handle(
          _uploadedAtMeta,
          uploadedAt.isAcceptableOrUnknown(
              data['uploaded_at']!, _uploadedAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packageId, assetId};
  @override
  UploadAssetEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadAssetEntry(
      packageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_id'])!,
      assetId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}asset_id'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      attemptCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempt_count'])!,
      errorCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_code']),
      uploadedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}uploaded_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $UploadAssetEntriesTable createAlias(String alias) {
    return $UploadAssetEntriesTable(attachedDatabase, alias);
  }
}

class UploadAssetEntry extends DataClass
    implements Insertable<UploadAssetEntry> {
  final String packageId;
  final String assetId;
  final String state;
  final int attemptCount;
  final String? errorCode;
  final DateTime? uploadedAt;
  final DateTime updatedAt;
  const UploadAssetEntry(
      {required this.packageId,
      required this.assetId,
      required this.state,
      required this.attemptCount,
      this.errorCode,
      this.uploadedAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['package_id'] = Variable<String>(packageId);
    map['asset_id'] = Variable<String>(assetId);
    map['state'] = Variable<String>(state);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || uploadedAt != null) {
      map['uploaded_at'] = Variable<DateTime>(uploadedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UploadAssetEntriesCompanion toCompanion(bool nullToAbsent) {
    return UploadAssetEntriesCompanion(
      packageId: Value(packageId),
      assetId: Value(assetId),
      state: Value(state),
      attemptCount: Value(attemptCount),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      uploadedAt: uploadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory UploadAssetEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadAssetEntry(
      packageId: serializer.fromJson<String>(json['packageId']),
      assetId: serializer.fromJson<String>(json['assetId']),
      state: serializer.fromJson<String>(json['state']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      uploadedAt: serializer.fromJson<DateTime?>(json['uploadedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packageId': serializer.toJson<String>(packageId),
      'assetId': serializer.toJson<String>(assetId),
      'state': serializer.toJson<String>(state),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'errorCode': serializer.toJson<String?>(errorCode),
      'uploadedAt': serializer.toJson<DateTime?>(uploadedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  UploadAssetEntry copyWith(
          {String? packageId,
          String? assetId,
          String? state,
          int? attemptCount,
          Value<String?> errorCode = const Value.absent(),
          Value<DateTime?> uploadedAt = const Value.absent(),
          DateTime? updatedAt}) =>
      UploadAssetEntry(
        packageId: packageId ?? this.packageId,
        assetId: assetId ?? this.assetId,
        state: state ?? this.state,
        attemptCount: attemptCount ?? this.attemptCount,
        errorCode: errorCode.present ? errorCode.value : this.errorCode,
        uploadedAt: uploadedAt.present ? uploadedAt.value : this.uploadedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  UploadAssetEntry copyWithCompanion(UploadAssetEntriesCompanion data) {
    return UploadAssetEntry(
      packageId: data.packageId.present ? data.packageId.value : this.packageId,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      state: data.state.present ? data.state.value : this.state,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      uploadedAt:
          data.uploadedAt.present ? data.uploadedAt.value : this.uploadedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadAssetEntry(')
          ..write('packageId: $packageId, ')
          ..write('assetId: $assetId, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('errorCode: $errorCode, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(packageId, assetId, state, attemptCount,
      errorCode, uploadedAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadAssetEntry &&
          other.packageId == this.packageId &&
          other.assetId == this.assetId &&
          other.state == this.state &&
          other.attemptCount == this.attemptCount &&
          other.errorCode == this.errorCode &&
          other.uploadedAt == this.uploadedAt &&
          other.updatedAt == this.updatedAt);
}

class UploadAssetEntriesCompanion extends UpdateCompanion<UploadAssetEntry> {
  final Value<String> packageId;
  final Value<String> assetId;
  final Value<String> state;
  final Value<int> attemptCount;
  final Value<String?> errorCode;
  final Value<DateTime?> uploadedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UploadAssetEntriesCompanion({
    this.packageId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadAssetEntriesCompanion.insert({
    required String packageId,
    required String assetId,
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : packageId = Value(packageId),
        assetId = Value(assetId),
        updatedAt = Value(updatedAt);
  static Insertable<UploadAssetEntry> custom({
    Expression<String>? packageId,
    Expression<String>? assetId,
    Expression<String>? state,
    Expression<int>? attemptCount,
    Expression<String>? errorCode,
    Expression<DateTime>? uploadedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packageId != null) 'package_id': packageId,
      if (assetId != null) 'asset_id': assetId,
      if (state != null) 'state': state,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (errorCode != null) 'error_code': errorCode,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadAssetEntriesCompanion copyWith(
      {Value<String>? packageId,
      Value<String>? assetId,
      Value<String>? state,
      Value<int>? attemptCount,
      Value<String?>? errorCode,
      Value<DateTime?>? uploadedAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return UploadAssetEntriesCompanion(
      packageId: packageId ?? this.packageId,
      assetId: assetId ?? this.assetId,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      errorCode: errorCode ?? this.errorCode,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packageId.present) {
      map['package_id'] = Variable<String>(packageId.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (uploadedAt.present) {
      map['uploaded_at'] = Variable<DateTime>(uploadedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadAssetEntriesCompanion(')
          ..write('packageId: $packageId, ')
          ..write('assetId: $assetId, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('errorCode: $errorCode, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AuthContextsTable authContexts = $AuthContextsTable(this);
  late final $CachedOrganizationsTable cachedOrganizations =
      $CachedOrganizationsTable(this);
  late final $CachedBuildingsTable cachedBuildings =
      $CachedBuildingsTable(this);
  late final $CachedPensTable cachedPens = $CachedPensTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $CaptureDraftsTable captureDrafts = $CaptureDraftsTable(this);
  late final $CaptureSetsTable captureSets = $CaptureSetsTable(this);
  late final $LocalMediaAssetsTable localMediaAssets =
      $LocalMediaAssetsTable(this);
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  late final $UploadAssetEntriesTable uploadAssetEntries =
      $UploadAssetEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        authContexts,
        cachedOrganizations,
        cachedBuildings,
        cachedPens,
        syncCursors,
        captureDrafts,
        captureSets,
        localMediaAssets,
        outboxEntries,
        uploadAssetEntries
      ];
}

typedef $$AuthContextsTableCreateCompanionBuilder = AuthContextsCompanion
    Function({
  required String subjectId,
  required String displayName,
  required String activeOrganizationId,
  required String activeOrganizationCode,
  required String activeOrganizationName,
  required String rolesJson,
  required DateTime lastVerifiedAt,
  Value<int> rowid,
});
typedef $$AuthContextsTableUpdateCompanionBuilder = AuthContextsCompanion
    Function({
  Value<String> subjectId,
  Value<String> displayName,
  Value<String> activeOrganizationId,
  Value<String> activeOrganizationCode,
  Value<String> activeOrganizationName,
  Value<String> rolesJson,
  Value<DateTime> lastVerifiedAt,
  Value<int> rowid,
});

class $$AuthContextsTableFilterComposer
    extends Composer<_$AppDatabase, $AuthContextsTable> {
  $$AuthContextsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
      column: $table.subjectId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get activeOrganizationId => $composableBuilder(
      column: $table.activeOrganizationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get activeOrganizationCode => $composableBuilder(
      column: $table.activeOrganizationCode,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get activeOrganizationName => $composableBuilder(
      column: $table.activeOrganizationName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rolesJson => $composableBuilder(
      column: $table.rolesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastVerifiedAt => $composableBuilder(
      column: $table.lastVerifiedAt,
      builder: (column) => ColumnFilters(column));
}

class $$AuthContextsTableOrderingComposer
    extends Composer<_$AppDatabase, $AuthContextsTable> {
  $$AuthContextsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
      column: $table.subjectId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get activeOrganizationId => $composableBuilder(
      column: $table.activeOrganizationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get activeOrganizationCode => $composableBuilder(
      column: $table.activeOrganizationCode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get activeOrganizationName => $composableBuilder(
      column: $table.activeOrganizationName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rolesJson => $composableBuilder(
      column: $table.rolesJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastVerifiedAt => $composableBuilder(
      column: $table.lastVerifiedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$AuthContextsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuthContextsTable> {
  $$AuthContextsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get activeOrganizationId => $composableBuilder(
      column: $table.activeOrganizationId, builder: (column) => column);

  GeneratedColumn<String> get activeOrganizationCode => $composableBuilder(
      column: $table.activeOrganizationCode, builder: (column) => column);

  GeneratedColumn<String> get activeOrganizationName => $composableBuilder(
      column: $table.activeOrganizationName, builder: (column) => column);

  GeneratedColumn<String> get rolesJson =>
      $composableBuilder(column: $table.rolesJson, builder: (column) => column);

  GeneratedColumn<DateTime> get lastVerifiedAt => $composableBuilder(
      column: $table.lastVerifiedAt, builder: (column) => column);
}

class $$AuthContextsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AuthContextsTable,
    AuthContext,
    $$AuthContextsTableFilterComposer,
    $$AuthContextsTableOrderingComposer,
    $$AuthContextsTableAnnotationComposer,
    $$AuthContextsTableCreateCompanionBuilder,
    $$AuthContextsTableUpdateCompanionBuilder,
    (
      AuthContext,
      BaseReferences<_$AppDatabase, $AuthContextsTable, AuthContext>
    ),
    AuthContext,
    PrefetchHooks Function()> {
  $$AuthContextsTableTableManager(_$AppDatabase db, $AuthContextsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuthContextsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuthContextsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuthContextsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> subjectId = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<String> activeOrganizationId = const Value.absent(),
            Value<String> activeOrganizationCode = const Value.absent(),
            Value<String> activeOrganizationName = const Value.absent(),
            Value<String> rolesJson = const Value.absent(),
            Value<DateTime> lastVerifiedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AuthContextsCompanion(
            subjectId: subjectId,
            displayName: displayName,
            activeOrganizationId: activeOrganizationId,
            activeOrganizationCode: activeOrganizationCode,
            activeOrganizationName: activeOrganizationName,
            rolesJson: rolesJson,
            lastVerifiedAt: lastVerifiedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String subjectId,
            required String displayName,
            required String activeOrganizationId,
            required String activeOrganizationCode,
            required String activeOrganizationName,
            required String rolesJson,
            required DateTime lastVerifiedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AuthContextsCompanion.insert(
            subjectId: subjectId,
            displayName: displayName,
            activeOrganizationId: activeOrganizationId,
            activeOrganizationCode: activeOrganizationCode,
            activeOrganizationName: activeOrganizationName,
            rolesJson: rolesJson,
            lastVerifiedAt: lastVerifiedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AuthContextsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AuthContextsTable,
    AuthContext,
    $$AuthContextsTableFilterComposer,
    $$AuthContextsTableOrderingComposer,
    $$AuthContextsTableAnnotationComposer,
    $$AuthContextsTableCreateCompanionBuilder,
    $$AuthContextsTableUpdateCompanionBuilder,
    (
      AuthContext,
      BaseReferences<_$AppDatabase, $AuthContextsTable, AuthContext>
    ),
    AuthContext,
    PrefetchHooks Function()>;
typedef $$CachedOrganizationsTableCreateCompanionBuilder
    = CachedOrganizationsCompanion Function({
  required String id,
  required String code,
  required String name,
  Value<bool> enabled,
  Value<int> syncVersion,
  required DateTime syncedAt,
  Value<int> rowid,
});
typedef $$CachedOrganizationsTableUpdateCompanionBuilder
    = CachedOrganizationsCompanion Function({
  Value<String> id,
  Value<String> code,
  Value<String> name,
  Value<bool> enabled,
  Value<int> syncVersion,
  Value<DateTime> syncedAt,
  Value<int> rowid,
});

class $$CachedOrganizationsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedOrganizationsTable> {
  $$CachedOrganizationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedOrganizationsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedOrganizationsTable> {
  $$CachedOrganizationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedOrganizationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedOrganizationsTable> {
  $$CachedOrganizationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$CachedOrganizationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedOrganizationsTable,
    CachedOrganization,
    $$CachedOrganizationsTableFilterComposer,
    $$CachedOrganizationsTableOrderingComposer,
    $$CachedOrganizationsTableAnnotationComposer,
    $$CachedOrganizationsTableCreateCompanionBuilder,
    $$CachedOrganizationsTableUpdateCompanionBuilder,
    (
      CachedOrganization,
      BaseReferences<_$AppDatabase, $CachedOrganizationsTable,
          CachedOrganization>
    ),
    CachedOrganization,
    PrefetchHooks Function()> {
  $$CachedOrganizationsTableTableManager(
      _$AppDatabase db, $CachedOrganizationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedOrganizationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedOrganizationsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedOrganizationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> code = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> syncVersion = const Value.absent(),
            Value<DateTime> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedOrganizationsCompanion(
            id: id,
            code: code,
            name: name,
            enabled: enabled,
            syncVersion: syncVersion,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String code,
            required String name,
            Value<bool> enabled = const Value.absent(),
            Value<int> syncVersion = const Value.absent(),
            required DateTime syncedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedOrganizationsCompanion.insert(
            id: id,
            code: code,
            name: name,
            enabled: enabled,
            syncVersion: syncVersion,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedOrganizationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedOrganizationsTable,
    CachedOrganization,
    $$CachedOrganizationsTableFilterComposer,
    $$CachedOrganizationsTableOrderingComposer,
    $$CachedOrganizationsTableAnnotationComposer,
    $$CachedOrganizationsTableCreateCompanionBuilder,
    $$CachedOrganizationsTableUpdateCompanionBuilder,
    (
      CachedOrganization,
      BaseReferences<_$AppDatabase, $CachedOrganizationsTable,
          CachedOrganization>
    ),
    CachedOrganization,
    PrefetchHooks Function()>;
typedef $$CachedBuildingsTableCreateCompanionBuilder = CachedBuildingsCompanion
    Function({
  required String id,
  required String organizationId,
  required String code,
  required String name,
  Value<bool> enabled,
  Value<int> syncVersion,
  Value<int> rowid,
});
typedef $$CachedBuildingsTableUpdateCompanionBuilder = CachedBuildingsCompanion
    Function({
  Value<String> id,
  Value<String> organizationId,
  Value<String> code,
  Value<String> name,
  Value<bool> enabled,
  Value<int> syncVersion,
  Value<int> rowid,
});

class $$CachedBuildingsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedBuildingsTable> {
  $$CachedBuildingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get organizationId => $composableBuilder(
      column: $table.organizationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => ColumnFilters(column));
}

class $$CachedBuildingsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedBuildingsTable> {
  $$CachedBuildingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get organizationId => $composableBuilder(
      column: $table.organizationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => ColumnOrderings(column));
}

class $$CachedBuildingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedBuildingsTable> {
  $$CachedBuildingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
      column: $table.organizationId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => column);
}

class $$CachedBuildingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedBuildingsTable,
    CachedBuilding,
    $$CachedBuildingsTableFilterComposer,
    $$CachedBuildingsTableOrderingComposer,
    $$CachedBuildingsTableAnnotationComposer,
    $$CachedBuildingsTableCreateCompanionBuilder,
    $$CachedBuildingsTableUpdateCompanionBuilder,
    (
      CachedBuilding,
      BaseReferences<_$AppDatabase, $CachedBuildingsTable, CachedBuilding>
    ),
    CachedBuilding,
    PrefetchHooks Function()> {
  $$CachedBuildingsTableTableManager(
      _$AppDatabase db, $CachedBuildingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedBuildingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedBuildingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedBuildingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> organizationId = const Value.absent(),
            Value<String> code = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> syncVersion = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedBuildingsCompanion(
            id: id,
            organizationId: organizationId,
            code: code,
            name: name,
            enabled: enabled,
            syncVersion: syncVersion,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String organizationId,
            required String code,
            required String name,
            Value<bool> enabled = const Value.absent(),
            Value<int> syncVersion = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedBuildingsCompanion.insert(
            id: id,
            organizationId: organizationId,
            code: code,
            name: name,
            enabled: enabled,
            syncVersion: syncVersion,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedBuildingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedBuildingsTable,
    CachedBuilding,
    $$CachedBuildingsTableFilterComposer,
    $$CachedBuildingsTableOrderingComposer,
    $$CachedBuildingsTableAnnotationComposer,
    $$CachedBuildingsTableCreateCompanionBuilder,
    $$CachedBuildingsTableUpdateCompanionBuilder,
    (
      CachedBuilding,
      BaseReferences<_$AppDatabase, $CachedBuildingsTable, CachedBuilding>
    ),
    CachedBuilding,
    PrefetchHooks Function()>;
typedef $$CachedPensTableCreateCompanionBuilder = CachedPensCompanion Function({
  required String id,
  required String buildingId,
  required String code,
  required String name,
  Value<bool> enabled,
  Value<int> syncVersion,
  Value<int> rowid,
});
typedef $$CachedPensTableUpdateCompanionBuilder = CachedPensCompanion Function({
  Value<String> id,
  Value<String> buildingId,
  Value<String> code,
  Value<String> name,
  Value<bool> enabled,
  Value<int> syncVersion,
  Value<int> rowid,
});

class $$CachedPensTableFilterComposer
    extends Composer<_$AppDatabase, $CachedPensTable> {
  $$CachedPensTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get buildingId => $composableBuilder(
      column: $table.buildingId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => ColumnFilters(column));
}

class $$CachedPensTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedPensTable> {
  $$CachedPensTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get buildingId => $composableBuilder(
      column: $table.buildingId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => ColumnOrderings(column));
}

class $$CachedPensTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedPensTable> {
  $$CachedPensTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get buildingId => $composableBuilder(
      column: $table.buildingId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get syncVersion => $composableBuilder(
      column: $table.syncVersion, builder: (column) => column);
}

class $$CachedPensTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedPensTable,
    CachedPen,
    $$CachedPensTableFilterComposer,
    $$CachedPensTableOrderingComposer,
    $$CachedPensTableAnnotationComposer,
    $$CachedPensTableCreateCompanionBuilder,
    $$CachedPensTableUpdateCompanionBuilder,
    (CachedPen, BaseReferences<_$AppDatabase, $CachedPensTable, CachedPen>),
    CachedPen,
    PrefetchHooks Function()> {
  $$CachedPensTableTableManager(_$AppDatabase db, $CachedPensTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPensTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPensTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPensTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> buildingId = const Value.absent(),
            Value<String> code = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> syncVersion = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedPensCompanion(
            id: id,
            buildingId: buildingId,
            code: code,
            name: name,
            enabled: enabled,
            syncVersion: syncVersion,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String buildingId,
            required String code,
            required String name,
            Value<bool> enabled = const Value.absent(),
            Value<int> syncVersion = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedPensCompanion.insert(
            id: id,
            buildingId: buildingId,
            code: code,
            name: name,
            enabled: enabled,
            syncVersion: syncVersion,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedPensTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedPensTable,
    CachedPen,
    $$CachedPensTableFilterComposer,
    $$CachedPensTableOrderingComposer,
    $$CachedPensTableAnnotationComposer,
    $$CachedPensTableCreateCompanionBuilder,
    $$CachedPensTableUpdateCompanionBuilder,
    (CachedPen, BaseReferences<_$AppDatabase, $CachedPensTable, CachedPen>),
    CachedPen,
    PrefetchHooks Function()>;
typedef $$SyncCursorsTableCreateCompanionBuilder = SyncCursorsCompanion
    Function({
  required String organizationId,
  required String cursor,
  required DateTime syncedAt,
  Value<int> rowid,
});
typedef $$SyncCursorsTableUpdateCompanionBuilder = SyncCursorsCompanion
    Function({
  Value<String> organizationId,
  Value<String> cursor,
  Value<DateTime> syncedAt,
  Value<int> rowid,
});

class $$SyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
      column: $table.organizationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cursor => $composableBuilder(
      column: $table.cursor, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
      column: $table.organizationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cursor => $composableBuilder(
      column: $table.cursor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
      column: $table.organizationId, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$SyncCursorsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncCursorsTable,
    SyncCursor,
    $$SyncCursorsTableFilterComposer,
    $$SyncCursorsTableOrderingComposer,
    $$SyncCursorsTableAnnotationComposer,
    $$SyncCursorsTableCreateCompanionBuilder,
    $$SyncCursorsTableUpdateCompanionBuilder,
    (SyncCursor, BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>),
    SyncCursor,
    PrefetchHooks Function()> {
  $$SyncCursorsTableTableManager(_$AppDatabase db, $SyncCursorsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> organizationId = const Value.absent(),
            Value<String> cursor = const Value.absent(),
            Value<DateTime> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncCursorsCompanion(
            organizationId: organizationId,
            cursor: cursor,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String organizationId,
            required String cursor,
            required DateTime syncedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncCursorsCompanion.insert(
            organizationId: organizationId,
            cursor: cursor,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncCursorsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncCursorsTable,
    SyncCursor,
    $$SyncCursorsTableFilterComposer,
    $$SyncCursorsTableOrderingComposer,
    $$SyncCursorsTableAnnotationComposer,
    $$SyncCursorsTableCreateCompanionBuilder,
    $$SyncCursorsTableUpdateCompanionBuilder,
    (SyncCursor, BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>),
    SyncCursor,
    PrefetchHooks Function()>;
typedef $$CaptureDraftsTableCreateCompanionBuilder = CaptureDraftsCompanion
    Function({
  required String id,
  required String organizationId,
  required String penId,
  required String captureKind,
  Value<String> state,
  required DateTime businessDate,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$CaptureDraftsTableUpdateCompanionBuilder = CaptureDraftsCompanion
    Function({
  Value<String> id,
  Value<String> organizationId,
  Value<String> penId,
  Value<String> captureKind,
  Value<String> state,
  Value<DateTime> businessDate,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CaptureDraftsTableFilterComposer
    extends Composer<_$AppDatabase, $CaptureDraftsTable> {
  $$CaptureDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get organizationId => $composableBuilder(
      column: $table.organizationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get penId => $composableBuilder(
      column: $table.penId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get captureKind => $composableBuilder(
      column: $table.captureKind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get businessDate => $composableBuilder(
      column: $table.businessDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CaptureDraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $CaptureDraftsTable> {
  $$CaptureDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get organizationId => $composableBuilder(
      column: $table.organizationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get penId => $composableBuilder(
      column: $table.penId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get captureKind => $composableBuilder(
      column: $table.captureKind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get businessDate => $composableBuilder(
      column: $table.businessDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CaptureDraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CaptureDraftsTable> {
  $$CaptureDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
      column: $table.organizationId, builder: (column) => column);

  GeneratedColumn<String> get penId =>
      $composableBuilder(column: $table.penId, builder: (column) => column);

  GeneratedColumn<String> get captureKind => $composableBuilder(
      column: $table.captureKind, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get businessDate => $composableBuilder(
      column: $table.businessDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CaptureDraftsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CaptureDraftsTable,
    CaptureDraft,
    $$CaptureDraftsTableFilterComposer,
    $$CaptureDraftsTableOrderingComposer,
    $$CaptureDraftsTableAnnotationComposer,
    $$CaptureDraftsTableCreateCompanionBuilder,
    $$CaptureDraftsTableUpdateCompanionBuilder,
    (
      CaptureDraft,
      BaseReferences<_$AppDatabase, $CaptureDraftsTable, CaptureDraft>
    ),
    CaptureDraft,
    PrefetchHooks Function()> {
  $$CaptureDraftsTableTableManager(_$AppDatabase db, $CaptureDraftsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CaptureDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CaptureDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CaptureDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> organizationId = const Value.absent(),
            Value<String> penId = const Value.absent(),
            Value<String> captureKind = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<DateTime> businessDate = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CaptureDraftsCompanion(
            id: id,
            organizationId: organizationId,
            penId: penId,
            captureKind: captureKind,
            state: state,
            businessDate: businessDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String organizationId,
            required String penId,
            required String captureKind,
            Value<String> state = const Value.absent(),
            required DateTime businessDate,
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CaptureDraftsCompanion.insert(
            id: id,
            organizationId: organizationId,
            penId: penId,
            captureKind: captureKind,
            state: state,
            businessDate: businessDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CaptureDraftsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CaptureDraftsTable,
    CaptureDraft,
    $$CaptureDraftsTableFilterComposer,
    $$CaptureDraftsTableOrderingComposer,
    $$CaptureDraftsTableAnnotationComposer,
    $$CaptureDraftsTableCreateCompanionBuilder,
    $$CaptureDraftsTableUpdateCompanionBuilder,
    (
      CaptureDraft,
      BaseReferences<_$AppDatabase, $CaptureDraftsTable, CaptureDraft>
    ),
    CaptureDraft,
    PrefetchHooks Function()>;
typedef $$CaptureSetsTableCreateCompanionBuilder = CaptureSetsCompanion
    Function({
  required String id,
  required String draftId,
  required String kind,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$CaptureSetsTableUpdateCompanionBuilder = CaptureSetsCompanion
    Function({
  Value<String> id,
  Value<String> draftId,
  Value<String> kind,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$CaptureSetsTableFilterComposer
    extends Composer<_$AppDatabase, $CaptureSetsTable> {
  $$CaptureSetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get draftId => $composableBuilder(
      column: $table.draftId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$CaptureSetsTableOrderingComposer
    extends Composer<_$AppDatabase, $CaptureSetsTable> {
  $$CaptureSetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get draftId => $composableBuilder(
      column: $table.draftId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$CaptureSetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CaptureSetsTable> {
  $$CaptureSetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get draftId =>
      $composableBuilder(column: $table.draftId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CaptureSetsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CaptureSetsTable,
    CaptureSet,
    $$CaptureSetsTableFilterComposer,
    $$CaptureSetsTableOrderingComposer,
    $$CaptureSetsTableAnnotationComposer,
    $$CaptureSetsTableCreateCompanionBuilder,
    $$CaptureSetsTableUpdateCompanionBuilder,
    (CaptureSet, BaseReferences<_$AppDatabase, $CaptureSetsTable, CaptureSet>),
    CaptureSet,
    PrefetchHooks Function()> {
  $$CaptureSetsTableTableManager(_$AppDatabase db, $CaptureSetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CaptureSetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CaptureSetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CaptureSetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> draftId = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CaptureSetsCompanion(
            id: id,
            draftId: draftId,
            kind: kind,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String draftId,
            required String kind,
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CaptureSetsCompanion.insert(
            id: id,
            draftId: draftId,
            kind: kind,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CaptureSetsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CaptureSetsTable,
    CaptureSet,
    $$CaptureSetsTableFilterComposer,
    $$CaptureSetsTableOrderingComposer,
    $$CaptureSetsTableAnnotationComposer,
    $$CaptureSetsTableCreateCompanionBuilder,
    $$CaptureSetsTableUpdateCompanionBuilder,
    (CaptureSet, BaseReferences<_$AppDatabase, $CaptureSetsTable, CaptureSet>),
    CaptureSet,
    PrefetchHooks Function()>;
typedef $$LocalMediaAssetsTableCreateCompanionBuilder
    = LocalMediaAssetsCompanion Function({
  required String id,
  required String draftId,
  required String viewPosition,
  required String materializedPath,
  required String originalName,
  required String contentType,
  required int byteSize,
  required String sha256,
  Value<String> roiJson,
  Value<String> exifJson,
  Value<DateTime?> capturedAt,
  Value<int?> width,
  Value<int?> height,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$LocalMediaAssetsTableUpdateCompanionBuilder
    = LocalMediaAssetsCompanion Function({
  Value<String> id,
  Value<String> draftId,
  Value<String> viewPosition,
  Value<String> materializedPath,
  Value<String> originalName,
  Value<String> contentType,
  Value<int> byteSize,
  Value<String> sha256,
  Value<String> roiJson,
  Value<String> exifJson,
  Value<DateTime?> capturedAt,
  Value<int?> width,
  Value<int?> height,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$LocalMediaAssetsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMediaAssetsTable> {
  $$LocalMediaAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get draftId => $composableBuilder(
      column: $table.draftId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get viewPosition => $composableBuilder(
      column: $table.viewPosition, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get materializedPath => $composableBuilder(
      column: $table.materializedPath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get originalName => $composableBuilder(
      column: $table.originalName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentType => $composableBuilder(
      column: $table.contentType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get byteSize => $composableBuilder(
      column: $table.byteSize, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sha256 => $composableBuilder(
      column: $table.sha256, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get roiJson => $composableBuilder(
      column: $table.roiJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exifJson => $composableBuilder(
      column: $table.exifJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$LocalMediaAssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMediaAssetsTable> {
  $$LocalMediaAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get draftId => $composableBuilder(
      column: $table.draftId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get viewPosition => $composableBuilder(
      column: $table.viewPosition,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get materializedPath => $composableBuilder(
      column: $table.materializedPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get originalName => $composableBuilder(
      column: $table.originalName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentType => $composableBuilder(
      column: $table.contentType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get byteSize => $composableBuilder(
      column: $table.byteSize, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sha256 => $composableBuilder(
      column: $table.sha256, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get roiJson => $composableBuilder(
      column: $table.roiJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exifJson => $composableBuilder(
      column: $table.exifJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalMediaAssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMediaAssetsTable> {
  $$LocalMediaAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get draftId =>
      $composableBuilder(column: $table.draftId, builder: (column) => column);

  GeneratedColumn<String> get viewPosition => $composableBuilder(
      column: $table.viewPosition, builder: (column) => column);

  GeneratedColumn<String> get materializedPath => $composableBuilder(
      column: $table.materializedPath, builder: (column) => column);

  GeneratedColumn<String> get originalName => $composableBuilder(
      column: $table.originalName, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
      column: $table.contentType, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get roiJson =>
      $composableBuilder(column: $table.roiJson, builder: (column) => column);

  GeneratedColumn<String> get exifJson =>
      $composableBuilder(column: $table.exifJson, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LocalMediaAssetsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalMediaAssetsTable,
    LocalMediaAsset,
    $$LocalMediaAssetsTableFilterComposer,
    $$LocalMediaAssetsTableOrderingComposer,
    $$LocalMediaAssetsTableAnnotationComposer,
    $$LocalMediaAssetsTableCreateCompanionBuilder,
    $$LocalMediaAssetsTableUpdateCompanionBuilder,
    (
      LocalMediaAsset,
      BaseReferences<_$AppDatabase, $LocalMediaAssetsTable, LocalMediaAsset>
    ),
    LocalMediaAsset,
    PrefetchHooks Function()> {
  $$LocalMediaAssetsTableTableManager(
      _$AppDatabase db, $LocalMediaAssetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMediaAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMediaAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMediaAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> draftId = const Value.absent(),
            Value<String> viewPosition = const Value.absent(),
            Value<String> materializedPath = const Value.absent(),
            Value<String> originalName = const Value.absent(),
            Value<String> contentType = const Value.absent(),
            Value<int> byteSize = const Value.absent(),
            Value<String> sha256 = const Value.absent(),
            Value<String> roiJson = const Value.absent(),
            Value<String> exifJson = const Value.absent(),
            Value<DateTime?> capturedAt = const Value.absent(),
            Value<int?> width = const Value.absent(),
            Value<int?> height = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalMediaAssetsCompanion(
            id: id,
            draftId: draftId,
            viewPosition: viewPosition,
            materializedPath: materializedPath,
            originalName: originalName,
            contentType: contentType,
            byteSize: byteSize,
            sha256: sha256,
            roiJson: roiJson,
            exifJson: exifJson,
            capturedAt: capturedAt,
            width: width,
            height: height,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String draftId,
            required String viewPosition,
            required String materializedPath,
            required String originalName,
            required String contentType,
            required int byteSize,
            required String sha256,
            Value<String> roiJson = const Value.absent(),
            Value<String> exifJson = const Value.absent(),
            Value<DateTime?> capturedAt = const Value.absent(),
            Value<int?> width = const Value.absent(),
            Value<int?> height = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalMediaAssetsCompanion.insert(
            id: id,
            draftId: draftId,
            viewPosition: viewPosition,
            materializedPath: materializedPath,
            originalName: originalName,
            contentType: contentType,
            byteSize: byteSize,
            sha256: sha256,
            roiJson: roiJson,
            exifJson: exifJson,
            capturedAt: capturedAt,
            width: width,
            height: height,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalMediaAssetsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalMediaAssetsTable,
    LocalMediaAsset,
    $$LocalMediaAssetsTableFilterComposer,
    $$LocalMediaAssetsTableOrderingComposer,
    $$LocalMediaAssetsTableAnnotationComposer,
    $$LocalMediaAssetsTableCreateCompanionBuilder,
    $$LocalMediaAssetsTableUpdateCompanionBuilder,
    (
      LocalMediaAsset,
      BaseReferences<_$AppDatabase, $LocalMediaAssetsTable, LocalMediaAsset>
    ),
    LocalMediaAsset,
    PrefetchHooks Function()>;
typedef $$OutboxEntriesTableCreateCompanionBuilder = OutboxEntriesCompanion
    Function({
  required String packageId,
  required String draftId,
  required String idempotencyKey,
  Value<String> state,
  required String manifestJson,
  Value<String?> error,
  Value<String?> serverPackageId,
  Value<String?> sessionId,
  Value<String?> inferenceJobId,
  Value<int> attemptCount,
  Value<DateTime?> nextAttemptAt,
  Value<String?> leaseOwner,
  Value<DateTime?> leaseExpiresAt,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$OutboxEntriesTableUpdateCompanionBuilder = OutboxEntriesCompanion
    Function({
  Value<String> packageId,
  Value<String> draftId,
  Value<String> idempotencyKey,
  Value<String> state,
  Value<String> manifestJson,
  Value<String?> error,
  Value<String?> serverPackageId,
  Value<String?> sessionId,
  Value<String?> inferenceJobId,
  Value<int> attemptCount,
  Value<DateTime?> nextAttemptAt,
  Value<String?> leaseOwner,
  Value<DateTime?> leaseExpiresAt,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$OutboxEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packageId => $composableBuilder(
      column: $table.packageId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get draftId => $composableBuilder(
      column: $table.draftId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get manifestJson => $composableBuilder(
      column: $table.manifestJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get error => $composableBuilder(
      column: $table.error, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverPackageId => $composableBuilder(
      column: $table.serverPackageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get inferenceJobId => $composableBuilder(
      column: $table.inferenceJobId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get leaseOwner => $composableBuilder(
      column: $table.leaseOwner, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get leaseExpiresAt => $composableBuilder(
      column: $table.leaseExpiresAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$OutboxEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packageId => $composableBuilder(
      column: $table.packageId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get draftId => $composableBuilder(
      column: $table.draftId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get manifestJson => $composableBuilder(
      column: $table.manifestJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get error => $composableBuilder(
      column: $table.error, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverPackageId => $composableBuilder(
      column: $table.serverPackageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get inferenceJobId => $composableBuilder(
      column: $table.inferenceJobId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get leaseOwner => $composableBuilder(
      column: $table.leaseOwner, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get leaseExpiresAt => $composableBuilder(
      column: $table.leaseExpiresAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$OutboxEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packageId =>
      $composableBuilder(column: $table.packageId, builder: (column) => column);

  GeneratedColumn<String> get draftId =>
      $composableBuilder(column: $table.draftId, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get manifestJson => $composableBuilder(
      column: $table.manifestJson, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<String> get serverPackageId => $composableBuilder(
      column: $table.serverPackageId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get inferenceJobId => $composableBuilder(
      column: $table.inferenceJobId, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt, builder: (column) => column);

  GeneratedColumn<String> get leaseOwner => $composableBuilder(
      column: $table.leaseOwner, builder: (column) => column);

  GeneratedColumn<DateTime> get leaseExpiresAt => $composableBuilder(
      column: $table.leaseExpiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OutboxEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OutboxEntriesTable,
    OutboxEntry,
    $$OutboxEntriesTableFilterComposer,
    $$OutboxEntriesTableOrderingComposer,
    $$OutboxEntriesTableAnnotationComposer,
    $$OutboxEntriesTableCreateCompanionBuilder,
    $$OutboxEntriesTableUpdateCompanionBuilder,
    (
      OutboxEntry,
      BaseReferences<_$AppDatabase, $OutboxEntriesTable, OutboxEntry>
    ),
    OutboxEntry,
    PrefetchHooks Function()> {
  $$OutboxEntriesTableTableManager(_$AppDatabase db, $OutboxEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> packageId = const Value.absent(),
            Value<String> draftId = const Value.absent(),
            Value<String> idempotencyKey = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<String> manifestJson = const Value.absent(),
            Value<String?> error = const Value.absent(),
            Value<String?> serverPackageId = const Value.absent(),
            Value<String?> sessionId = const Value.absent(),
            Value<String?> inferenceJobId = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<DateTime?> nextAttemptAt = const Value.absent(),
            Value<String?> leaseOwner = const Value.absent(),
            Value<DateTime?> leaseExpiresAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxEntriesCompanion(
            packageId: packageId,
            draftId: draftId,
            idempotencyKey: idempotencyKey,
            state: state,
            manifestJson: manifestJson,
            error: error,
            serverPackageId: serverPackageId,
            sessionId: sessionId,
            inferenceJobId: inferenceJobId,
            attemptCount: attemptCount,
            nextAttemptAt: nextAttemptAt,
            leaseOwner: leaseOwner,
            leaseExpiresAt: leaseExpiresAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String packageId,
            required String draftId,
            required String idempotencyKey,
            Value<String> state = const Value.absent(),
            required String manifestJson,
            Value<String?> error = const Value.absent(),
            Value<String?> serverPackageId = const Value.absent(),
            Value<String?> sessionId = const Value.absent(),
            Value<String?> inferenceJobId = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<DateTime?> nextAttemptAt = const Value.absent(),
            Value<String?> leaseOwner = const Value.absent(),
            Value<DateTime?> leaseExpiresAt = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxEntriesCompanion.insert(
            packageId: packageId,
            draftId: draftId,
            idempotencyKey: idempotencyKey,
            state: state,
            manifestJson: manifestJson,
            error: error,
            serverPackageId: serverPackageId,
            sessionId: sessionId,
            inferenceJobId: inferenceJobId,
            attemptCount: attemptCount,
            nextAttemptAt: nextAttemptAt,
            leaseOwner: leaseOwner,
            leaseExpiresAt: leaseExpiresAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OutboxEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OutboxEntriesTable,
    OutboxEntry,
    $$OutboxEntriesTableFilterComposer,
    $$OutboxEntriesTableOrderingComposer,
    $$OutboxEntriesTableAnnotationComposer,
    $$OutboxEntriesTableCreateCompanionBuilder,
    $$OutboxEntriesTableUpdateCompanionBuilder,
    (
      OutboxEntry,
      BaseReferences<_$AppDatabase, $OutboxEntriesTable, OutboxEntry>
    ),
    OutboxEntry,
    PrefetchHooks Function()>;
typedef $$UploadAssetEntriesTableCreateCompanionBuilder
    = UploadAssetEntriesCompanion Function({
  required String packageId,
  required String assetId,
  Value<String> state,
  Value<int> attemptCount,
  Value<String?> errorCode,
  Value<DateTime?> uploadedAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$UploadAssetEntriesTableUpdateCompanionBuilder
    = UploadAssetEntriesCompanion Function({
  Value<String> packageId,
  Value<String> assetId,
  Value<String> state,
  Value<int> attemptCount,
  Value<String?> errorCode,
  Value<DateTime?> uploadedAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$UploadAssetEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $UploadAssetEntriesTable> {
  $$UploadAssetEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packageId => $composableBuilder(
      column: $table.packageId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get assetId => $composableBuilder(
      column: $table.assetId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorCode => $composableBuilder(
      column: $table.errorCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get uploadedAt => $composableBuilder(
      column: $table.uploadedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$UploadAssetEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadAssetEntriesTable> {
  $$UploadAssetEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packageId => $composableBuilder(
      column: $table.packageId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get assetId => $composableBuilder(
      column: $table.assetId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorCode => $composableBuilder(
      column: $table.errorCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get uploadedAt => $composableBuilder(
      column: $table.uploadedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$UploadAssetEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadAssetEntriesTable> {
  $$UploadAssetEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packageId =>
      $composableBuilder(column: $table.packageId, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<DateTime> get uploadedAt => $composableBuilder(
      column: $table.uploadedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$UploadAssetEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UploadAssetEntriesTable,
    UploadAssetEntry,
    $$UploadAssetEntriesTableFilterComposer,
    $$UploadAssetEntriesTableOrderingComposer,
    $$UploadAssetEntriesTableAnnotationComposer,
    $$UploadAssetEntriesTableCreateCompanionBuilder,
    $$UploadAssetEntriesTableUpdateCompanionBuilder,
    (
      UploadAssetEntry,
      BaseReferences<_$AppDatabase, $UploadAssetEntriesTable, UploadAssetEntry>
    ),
    UploadAssetEntry,
    PrefetchHooks Function()> {
  $$UploadAssetEntriesTableTableManager(
      _$AppDatabase db, $UploadAssetEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadAssetEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadAssetEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadAssetEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> packageId = const Value.absent(),
            Value<String> assetId = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<String?> errorCode = const Value.absent(),
            Value<DateTime?> uploadedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UploadAssetEntriesCompanion(
            packageId: packageId,
            assetId: assetId,
            state: state,
            attemptCount: attemptCount,
            errorCode: errorCode,
            uploadedAt: uploadedAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String packageId,
            required String assetId,
            Value<String> state = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<String?> errorCode = const Value.absent(),
            Value<DateTime?> uploadedAt = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              UploadAssetEntriesCompanion.insert(
            packageId: packageId,
            assetId: assetId,
            state: state,
            attemptCount: attemptCount,
            errorCode: errorCode,
            uploadedAt: uploadedAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UploadAssetEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UploadAssetEntriesTable,
    UploadAssetEntry,
    $$UploadAssetEntriesTableFilterComposer,
    $$UploadAssetEntriesTableOrderingComposer,
    $$UploadAssetEntriesTableAnnotationComposer,
    $$UploadAssetEntriesTableCreateCompanionBuilder,
    $$UploadAssetEntriesTableUpdateCompanionBuilder,
    (
      UploadAssetEntry,
      BaseReferences<_$AppDatabase, $UploadAssetEntriesTable, UploadAssetEntry>
    ),
    UploadAssetEntry,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AuthContextsTableTableManager get authContexts =>
      $$AuthContextsTableTableManager(_db, _db.authContexts);
  $$CachedOrganizationsTableTableManager get cachedOrganizations =>
      $$CachedOrganizationsTableTableManager(_db, _db.cachedOrganizations);
  $$CachedBuildingsTableTableManager get cachedBuildings =>
      $$CachedBuildingsTableTableManager(_db, _db.cachedBuildings);
  $$CachedPensTableTableManager get cachedPens =>
      $$CachedPensTableTableManager(_db, _db.cachedPens);
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$CaptureDraftsTableTableManager get captureDrafts =>
      $$CaptureDraftsTableTableManager(_db, _db.captureDrafts);
  $$CaptureSetsTableTableManager get captureSets =>
      $$CaptureSetsTableTableManager(_db, _db.captureSets);
  $$LocalMediaAssetsTableTableManager get localMediaAssets =>
      $$LocalMediaAssetsTableTableManager(_db, _db.localMediaAssets);
  $$OutboxEntriesTableTableManager get outboxEntries =>
      $$OutboxEntriesTableTableManager(_db, _db.outboxEntries);
  $$UploadAssetEntriesTableTableManager get uploadAssetEntries =>
      $$UploadAssetEntriesTableTableManager(_db, _db.uploadAssetEntries);
}
