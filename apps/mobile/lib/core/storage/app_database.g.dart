// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
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
      type: DriftSqlType.string, requiredDuringInsert: true);
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
  final DateTime createdAt;
  final DateTime updatedAt;
  const OutboxEntry(
      {required this.packageId,
      required this.draftId,
      required this.idempotencyKey,
      required this.state,
      required this.manifestJson,
      this.error,
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
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      OutboxEntry(
        packageId: packageId ?? this.packageId,
        draftId: draftId ?? this.draftId,
        idempotencyKey: idempotencyKey ?? this.idempotencyKey,
        state: state ?? this.state,
        manifestJson: manifestJson ?? this.manifestJson,
        error: error.present ? error.value : this.error,
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
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(packageId, draftId, idempotencyKey, state,
      manifestJson, error, createdAt, updatedAt);
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
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedOrganizationsTable cachedOrganizations =
      $CachedOrganizationsTable(this);
  late final $CachedBuildingsTable cachedBuildings =
      $CachedBuildingsTable(this);
  late final $CachedPensTable cachedPens = $CachedPensTable(this);
  late final $CaptureDraftsTable captureDrafts = $CaptureDraftsTable(this);
  late final $LocalMediaAssetsTable localMediaAssets =
      $LocalMediaAssetsTable(this);
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        cachedOrganizations,
        cachedBuildings,
        cachedPens,
        captureDrafts,
        localMediaAssets,
        outboxEntries
      ];
}

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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedOrganizationsTableTableManager get cachedOrganizations =>
      $$CachedOrganizationsTableTableManager(_db, _db.cachedOrganizations);
  $$CachedBuildingsTableTableManager get cachedBuildings =>
      $$CachedBuildingsTableTableManager(_db, _db.cachedBuildings);
  $$CachedPensTableTableManager get cachedPens =>
      $$CachedPensTableTableManager(_db, _db.cachedPens);
  $$CaptureDraftsTableTableManager get captureDrafts =>
      $$CaptureDraftsTableTableManager(_db, _db.captureDrafts);
  $$LocalMediaAssetsTableTableManager get localMediaAssets =>
      $$LocalMediaAssetsTableTableManager(_db, _db.localMediaAssets);
  $$OutboxEntriesTableTableManager get outboxEntries =>
      $$OutboxEntriesTableTableManager(_db, _db.outboxEntries);
}
