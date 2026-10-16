// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedFeedsTable extends CachedFeeds
    with TableInfo<$CachedFeedsTable, CachedFeed> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedFeedsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonPayloadMeta = const VerificationMeta(
    'jsonPayload',
  );
  @override
  late final GeneratedColumn<String> jsonPayload = GeneratedColumn<String>(
    'json_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, jsonPayload, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_feeds';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFeed> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('json_payload')) {
      context.handle(
        _jsonPayloadMeta,
        jsonPayload.isAcceptableOrUnknown(
          data['json_payload']!,
          _jsonPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_jsonPayloadMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CachedFeed map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFeed(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      jsonPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json_payload'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedFeedsTable createAlias(String alias) {
    return $CachedFeedsTable(attachedDatabase, alias);
  }
}

class CachedFeed extends DataClass implements Insertable<CachedFeed> {
  final String key;
  final String jsonPayload;
  final DateTime updatedAt;
  const CachedFeed({
    required this.key,
    required this.jsonPayload,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['json_payload'] = Variable<String>(jsonPayload);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedFeedsCompanion toCompanion(bool nullToAbsent) {
    return CachedFeedsCompanion(
      key: Value(key),
      jsonPayload: Value(jsonPayload),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedFeed.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFeed(
      key: serializer.fromJson<String>(json['key']),
      jsonPayload: serializer.fromJson<String>(json['jsonPayload']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'jsonPayload': serializer.toJson<String>(jsonPayload),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedFeed copyWith({
    String? key,
    String? jsonPayload,
    DateTime? updatedAt,
  }) => CachedFeed(
    key: key ?? this.key,
    jsonPayload: jsonPayload ?? this.jsonPayload,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedFeed copyWithCompanion(CachedFeedsCompanion data) {
    return CachedFeed(
      key: data.key.present ? data.key.value : this.key,
      jsonPayload: data.jsonPayload.present
          ? data.jsonPayload.value
          : this.jsonPayload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFeed(')
          ..write('key: $key, ')
          ..write('jsonPayload: $jsonPayload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, jsonPayload, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFeed &&
          other.key == this.key &&
          other.jsonPayload == this.jsonPayload &&
          other.updatedAt == this.updatedAt);
}

class CachedFeedsCompanion extends UpdateCompanion<CachedFeed> {
  final Value<String> key;
  final Value<String> jsonPayload;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedFeedsCompanion({
    this.key = const Value.absent(),
    this.jsonPayload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedFeedsCompanion.insert({
    required String key,
    required String jsonPayload,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       jsonPayload = Value(jsonPayload),
       updatedAt = Value(updatedAt);
  static Insertable<CachedFeed> custom({
    Expression<String>? key,
    Expression<String>? jsonPayload,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (jsonPayload != null) 'json_payload': jsonPayload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedFeedsCompanion copyWith({
    Value<String>? key,
    Value<String>? jsonPayload,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedFeedsCompanion(
      key: key ?? this.key,
      jsonPayload: jsonPayload ?? this.jsonPayload,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (jsonPayload.present) {
      map['json_payload'] = Variable<String>(jsonPayload.value);
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
    return (StringBuffer('CachedFeedsCompanion(')
          ..write('key: $key, ')
          ..write('jsonPayload: $jsonPayload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedRegimenSlotsTable extends SavedRegimenSlots
    with TableInfo<$SavedRegimenSlotsTable, SavedRegimenSlot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedRegimenSlotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetWeekdayMeta = const VerificationMeta(
    'targetWeekday',
  );
  @override
  late final GeneratedColumn<int> targetWeekday = GeneratedColumn<int>(
    'target_weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetStartMinMeta = const VerificationMeta(
    'targetStartMin',
  );
  @override
  late final GeneratedColumn<int> targetStartMin = GeneratedColumn<int>(
    'target_start_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    templateId,
    targetWeekday,
    targetStartMin,
    label,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_regimen_slots';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedRegimenSlot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('target_weekday')) {
      context.handle(
        _targetWeekdayMeta,
        targetWeekday.isAcceptableOrUnknown(
          data['target_weekday']!,
          _targetWeekdayMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetWeekdayMeta);
    }
    if (data.containsKey('target_start_min')) {
      context.handle(
        _targetStartMinMeta,
        targetStartMin.isAcceptableOrUnknown(
          data['target_start_min']!,
          _targetStartMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetStartMinMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedRegimenSlot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedRegimenSlot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      )!,
      targetWeekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_weekday'],
      )!,
      targetStartMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_start_min'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SavedRegimenSlotsTable createAlias(String alias) {
    return $SavedRegimenSlotsTable(attachedDatabase, alias);
  }
}

class SavedRegimenSlot extends DataClass
    implements Insertable<SavedRegimenSlot> {
  final String id;
  final String templateId;
  final int targetWeekday;
  final int targetStartMin;
  final String label;
  final DateTime createdAt;
  const SavedRegimenSlot({
    required this.id,
    required this.templateId,
    required this.targetWeekday,
    required this.targetStartMin,
    required this.label,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['template_id'] = Variable<String>(templateId);
    map['target_weekday'] = Variable<int>(targetWeekday);
    map['target_start_min'] = Variable<int>(targetStartMin);
    map['label'] = Variable<String>(label);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SavedRegimenSlotsCompanion toCompanion(bool nullToAbsent) {
    return SavedRegimenSlotsCompanion(
      id: Value(id),
      templateId: Value(templateId),
      targetWeekday: Value(targetWeekday),
      targetStartMin: Value(targetStartMin),
      label: Value(label),
      createdAt: Value(createdAt),
    );
  }

  factory SavedRegimenSlot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedRegimenSlot(
      id: serializer.fromJson<String>(json['id']),
      templateId: serializer.fromJson<String>(json['templateId']),
      targetWeekday: serializer.fromJson<int>(json['targetWeekday']),
      targetStartMin: serializer.fromJson<int>(json['targetStartMin']),
      label: serializer.fromJson<String>(json['label']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'templateId': serializer.toJson<String>(templateId),
      'targetWeekday': serializer.toJson<int>(targetWeekday),
      'targetStartMin': serializer.toJson<int>(targetStartMin),
      'label': serializer.toJson<String>(label),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SavedRegimenSlot copyWith({
    String? id,
    String? templateId,
    int? targetWeekday,
    int? targetStartMin,
    String? label,
    DateTime? createdAt,
  }) => SavedRegimenSlot(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    targetWeekday: targetWeekday ?? this.targetWeekday,
    targetStartMin: targetStartMin ?? this.targetStartMin,
    label: label ?? this.label,
    createdAt: createdAt ?? this.createdAt,
  );
  SavedRegimenSlot copyWithCompanion(SavedRegimenSlotsCompanion data) {
    return SavedRegimenSlot(
      id: data.id.present ? data.id.value : this.id,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      targetWeekday: data.targetWeekday.present
          ? data.targetWeekday.value
          : this.targetWeekday,
      targetStartMin: data.targetStartMin.present
          ? data.targetStartMin.value
          : this.targetStartMin,
      label: data.label.present ? data.label.value : this.label,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedRegimenSlot(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('targetWeekday: $targetWeekday, ')
          ..write('targetStartMin: $targetStartMin, ')
          ..write('label: $label, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    templateId,
    targetWeekday,
    targetStartMin,
    label,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedRegimenSlot &&
          other.id == this.id &&
          other.templateId == this.templateId &&
          other.targetWeekday == this.targetWeekday &&
          other.targetStartMin == this.targetStartMin &&
          other.label == this.label &&
          other.createdAt == this.createdAt);
}

class SavedRegimenSlotsCompanion extends UpdateCompanion<SavedRegimenSlot> {
  final Value<String> id;
  final Value<String> templateId;
  final Value<int> targetWeekday;
  final Value<int> targetStartMin;
  final Value<String> label;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SavedRegimenSlotsCompanion({
    this.id = const Value.absent(),
    this.templateId = const Value.absent(),
    this.targetWeekday = const Value.absent(),
    this.targetStartMin = const Value.absent(),
    this.label = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedRegimenSlotsCompanion.insert({
    required String id,
    required String templateId,
    required int targetWeekday,
    required int targetStartMin,
    required String label,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       templateId = Value(templateId),
       targetWeekday = Value(targetWeekday),
       targetStartMin = Value(targetStartMin),
       label = Value(label),
       createdAt = Value(createdAt);
  static Insertable<SavedRegimenSlot> custom({
    Expression<String>? id,
    Expression<String>? templateId,
    Expression<int>? targetWeekday,
    Expression<int>? targetStartMin,
    Expression<String>? label,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (templateId != null) 'template_id': templateId,
      if (targetWeekday != null) 'target_weekday': targetWeekday,
      if (targetStartMin != null) 'target_start_min': targetStartMin,
      if (label != null) 'label': label,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedRegimenSlotsCompanion copyWith({
    Value<String>? id,
    Value<String>? templateId,
    Value<int>? targetWeekday,
    Value<int>? targetStartMin,
    Value<String>? label,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SavedRegimenSlotsCompanion(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      targetWeekday: targetWeekday ?? this.targetWeekday,
      targetStartMin: targetStartMin ?? this.targetStartMin,
      label: label ?? this.label,
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
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (targetWeekday.present) {
      map['target_weekday'] = Variable<int>(targetWeekday.value);
    }
    if (targetStartMin.present) {
      map['target_start_min'] = Variable<int>(targetStartMin.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
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
    return (StringBuffer('SavedRegimenSlotsCompanion(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('targetWeekday: $targetWeekday, ')
          ..write('targetStartMin: $targetStartMin, ')
          ..write('label: $label, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserSettingsTable extends UserSettings
    with TableInfo<$UserSettingsTable, UserSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  UserSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $UserSettingsTable createAlias(String alias) {
    return $UserSettingsTable(attachedDatabase, alias);
  }
}

class UserSetting extends DataClass implements Insertable<UserSetting> {
  final String key;
  final String value;
  const UserSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  UserSettingsCompanion toCompanion(bool nullToAbsent) {
    return UserSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory UserSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  UserSetting copyWith({String? key, String? value}) =>
      UserSetting(key: key ?? this.key, value: value ?? this.value);
  UserSetting copyWithCompanion(UserSettingsCompanion data) {
    return UserSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class UserSettingsCompanion extends UpdateCompanion<UserSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const UserSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<UserSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return UserSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedFeedsTable cachedFeeds = $CachedFeedsTable(this);
  late final $SavedRegimenSlotsTable savedRegimenSlots =
      $SavedRegimenSlotsTable(this);
  late final $UserSettingsTable userSettings = $UserSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedFeeds,
    savedRegimenSlots,
    userSettings,
  ];
}

typedef $$CachedFeedsTableCreateCompanionBuilder =
    CachedFeedsCompanion Function({
      required String key,
      required String jsonPayload,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedFeedsTableUpdateCompanionBuilder =
    CachedFeedsCompanion Function({
      Value<String> key,
      Value<String> jsonPayload,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedFeedsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedFeedsTable> {
  $$CachedFeedsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jsonPayload => $composableBuilder(
    column: $table.jsonPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedFeedsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedFeedsTable> {
  $$CachedFeedsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jsonPayload => $composableBuilder(
    column: $table.jsonPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedFeedsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedFeedsTable> {
  $$CachedFeedsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get jsonPayload => $composableBuilder(
    column: $table.jsonPayload,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedFeedsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedFeedsTable,
          CachedFeed,
          $$CachedFeedsTableFilterComposer,
          $$CachedFeedsTableOrderingComposer,
          $$CachedFeedsTableAnnotationComposer,
          $$CachedFeedsTableCreateCompanionBuilder,
          $$CachedFeedsTableUpdateCompanionBuilder,
          (
            CachedFeed,
            BaseReferences<_$AppDatabase, $CachedFeedsTable, CachedFeed>,
          ),
          CachedFeed,
          PrefetchHooks Function()
        > {
  $$CachedFeedsTableTableManager(_$AppDatabase db, $CachedFeedsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedFeedsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedFeedsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedFeedsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> jsonPayload = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFeedsCompanion(
                key: key,
                jsonPayload: jsonPayload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String jsonPayload,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedFeedsCompanion.insert(
                key: key,
                jsonPayload: jsonPayload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedFeedsTable, CachedFeed>(table),
                  BaseReferences<_$AppDatabase, $CachedFeedsTable, CachedFeed>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedFeedsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedFeedsTable,
      CachedFeed,
      $$CachedFeedsTableFilterComposer,
      $$CachedFeedsTableOrderingComposer,
      $$CachedFeedsTableAnnotationComposer,
      $$CachedFeedsTableCreateCompanionBuilder,
      $$CachedFeedsTableUpdateCompanionBuilder,
      (
        CachedFeed,
        BaseReferences<_$AppDatabase, $CachedFeedsTable, CachedFeed>,
      ),
      CachedFeed,
      PrefetchHooks Function()
    >;
typedef $$SavedRegimenSlotsTableCreateCompanionBuilder =
    SavedRegimenSlotsCompanion Function({
      required String id,
      required String templateId,
      required int targetWeekday,
      required int targetStartMin,
      required String label,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$SavedRegimenSlotsTableUpdateCompanionBuilder =
    SavedRegimenSlotsCompanion Function({
      Value<String> id,
      Value<String> templateId,
      Value<int> targetWeekday,
      Value<int> targetStartMin,
      Value<String> label,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SavedRegimenSlotsTableFilterComposer
    extends Composer<_$AppDatabase, $SavedRegimenSlotsTable> {
  $$SavedRegimenSlotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetWeekday => $composableBuilder(
    column: $table.targetWeekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetStartMin => $composableBuilder(
    column: $table.targetStartMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedRegimenSlotsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedRegimenSlotsTable> {
  $$SavedRegimenSlotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetWeekday => $composableBuilder(
    column: $table.targetWeekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetStartMin => $composableBuilder(
    column: $table.targetStartMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedRegimenSlotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedRegimenSlotsTable> {
  $$SavedRegimenSlotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetWeekday => $composableBuilder(
    column: $table.targetWeekday,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetStartMin => $composableBuilder(
    column: $table.targetStartMin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SavedRegimenSlotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedRegimenSlotsTable,
          SavedRegimenSlot,
          $$SavedRegimenSlotsTableFilterComposer,
          $$SavedRegimenSlotsTableOrderingComposer,
          $$SavedRegimenSlotsTableAnnotationComposer,
          $$SavedRegimenSlotsTableCreateCompanionBuilder,
          $$SavedRegimenSlotsTableUpdateCompanionBuilder,
          (
            SavedRegimenSlot,
            BaseReferences<
              _$AppDatabase,
              $SavedRegimenSlotsTable,
              SavedRegimenSlot
            >,
          ),
          SavedRegimenSlot,
          PrefetchHooks Function()
        > {
  $$SavedRegimenSlotsTableTableManager(
    _$AppDatabase db,
    $SavedRegimenSlotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedRegimenSlotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedRegimenSlotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedRegimenSlotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> templateId = const Value.absent(),
                Value<int> targetWeekday = const Value.absent(),
                Value<int> targetStartMin = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedRegimenSlotsCompanion(
                id: id,
                templateId: templateId,
                targetWeekday: targetWeekday,
                targetStartMin: targetStartMin,
                label: label,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String templateId,
                required int targetWeekday,
                required int targetStartMin,
                required String label,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SavedRegimenSlotsCompanion.insert(
                id: id,
                templateId: templateId,
                targetWeekday: targetWeekday,
                targetStartMin: targetStartMin,
                label: label,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SavedRegimenSlotsTable, SavedRegimenSlot>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SavedRegimenSlotsTable,
                    SavedRegimenSlot
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedRegimenSlotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedRegimenSlotsTable,
      SavedRegimenSlot,
      $$SavedRegimenSlotsTableFilterComposer,
      $$SavedRegimenSlotsTableOrderingComposer,
      $$SavedRegimenSlotsTableAnnotationComposer,
      $$SavedRegimenSlotsTableCreateCompanionBuilder,
      $$SavedRegimenSlotsTableUpdateCompanionBuilder,
      (
        SavedRegimenSlot,
        BaseReferences<
          _$AppDatabase,
          $SavedRegimenSlotsTable,
          SavedRegimenSlot
        >,
      ),
      SavedRegimenSlot,
      PrefetchHooks Function()
    >;
typedef $$UserSettingsTableCreateCompanionBuilder =
    UserSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$UserSettingsTableUpdateCompanionBuilder =
    UserSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$UserSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$UserSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserSettingsTable,
          UserSetting,
          $$UserSettingsTableFilterComposer,
          $$UserSettingsTableOrderingComposer,
          $$UserSettingsTableAnnotationComposer,
          $$UserSettingsTableCreateCompanionBuilder,
          $$UserSettingsTableUpdateCompanionBuilder,
          (
            UserSetting,
            BaseReferences<_$AppDatabase, $UserSettingsTable, UserSetting>,
          ),
          UserSetting,
          PrefetchHooks Function()
        > {
  $$UserSettingsTableTableManager(_$AppDatabase db, $UserSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => UserSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => UserSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UserSettingsTable, UserSetting>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $UserSettingsTable,
                    UserSetting
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserSettingsTable,
      UserSetting,
      $$UserSettingsTableFilterComposer,
      $$UserSettingsTableOrderingComposer,
      $$UserSettingsTableAnnotationComposer,
      $$UserSettingsTableCreateCompanionBuilder,
      $$UserSettingsTableUpdateCompanionBuilder,
      (
        UserSetting,
        BaseReferences<_$AppDatabase, $UserSettingsTable, UserSetting>,
      ),
      UserSetting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedFeedsTableTableManager get cachedFeeds =>
      $$CachedFeedsTableTableManager(_db, _db.cachedFeeds);
  $$SavedRegimenSlotsTableTableManager get savedRegimenSlots =>
      $$SavedRegimenSlotsTableTableManager(_db, _db.savedRegimenSlots);
  $$UserSettingsTableTableManager get userSettings =>
      $$UserSettingsTableTableManager(_db, _db.userSettings);
}
