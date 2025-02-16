library jaguar_orm.generator.writer;

import 'package:collection/collection.dart';
import 'package:jaguar_orm_gen/src/model/model.dart';

class Writer {
  final StringBuffer _w = StringBuffer();

  final WriterModel _b;

  Writer(this._b) {
    _generate();
  }

  void _generate() {
    _w.writeln('mixin _${_b.name} implements Bean<${_b.modelType}> {');

    for (Field field in _b.fields.values) {
      _writeln(
          "final ${field.field} = ${field.vType}('${_camToSnak(field.colName)}');");
    }

    _writeFieldsMap();

    _writeFromMap();

    _writeToSetColumns();

    _writeCreate();

    _writeCrud();

    // TODO get by foreign for non-beaned

    // TODO remove by foreign for non-beaned

    for (BelongsToAssociation ass in _b.belongTos.values) {
      _writeFindOneByBeanedAssociation(ass);
      _writeFindListByBeanedAssociationList(ass);
      _removeByForeign(ass);

      _writeAssociate(ass);

      if (ass.belongsToMany) {
        _writeDetach(ass);
        _writeFetchOther(ass);
      }
    }

    for (BeanedForeignAssociation ass in _b.beanedForeignAssociations.values) {
      _writeFindOneByBeanedAssociation(ass);
      _writeFindListByBeanedAssociationList(ass);
      // TODO remove
    }

    _writeAttach();

    _writePreload();

    _writePreloadAll();

    _writeBeans();

    _w.writeln('}');
  }

  void _writeFieldsMap() {
    _w.writeln('Map<String, Field>? _fields;');

    _w.writeln('Map<String, Field> get fields => _fields ??= {');
    for (Field f in _b.fields.values) {
      _w.writeln('${f.field}.name: ${f.field},');
    }
    _w.writeln('};');
  }

  void _writeFromMap() {
    _w.writeln('${_b.modelType} fromMap(Map map) {');
    _w.write('${_b.modelType} model = ${_b.modelType}(');
    _b.fields.values.forEach((Field field) {
      if (field.isFinal) {
        _w.write(
            '${field.field}: adapter.parseValue(map[\'${_camToSnak(field.colName)}\']),');
      }
    });
    _w.writeln(');');

    _b.fields.values.forEach((Field field) {
      if (!field.isFinal) {
        _w.writeln(
            "model.${field.field} = adapter.parseValue(map['${_camToSnak(field.colName)}']);");
      }
    });

    _w.writeln();
    _w.writeln('return model;');
    _w.writeln('}');
  }

  void _writeCreate() {
    _w.writeln('Future<void> createTable({bool ifNotExists = false}) async {');
    _writeln('final st = Sql.create(tableName, ifNotExists: ifNotExists);');
    for (final Field f in _b.fields.values) {
      _write('st.add');

      if (f.type.startsWith('String')) {
        _write('Str');
      } else if (f.type.startsWith('bool')) {
        _write('Bool');
      } else if (f.type.startsWith('int')) {
        _write('Int');
      } else if (f.type.startsWith('num') || f.type.startsWith('double')) {
        _write('Double');
      } else if (f.type.startsWith('DateTime')) {
        _write('DateTime');
      } else {
        throw Exception('Invalid column data type!');
      }
      _write('(');
      _write('${f.field}.name');

      if (f.isPrimary) {
        _write(', primary: true');
      }

      if (f.foreign != null) {
        final foreign = f.foreign;
        if (foreign is BelongsToForeign) {
          _write(', foreignTable: ${foreign.beanInstanceName}.tableName');
          _write(
              ", foreignCol: ${foreign.beanInstanceName}.${foreign.refCol}.name");
        } else {
          throw Exception('Unimplemented!');
        }
      }

      if (f.autoIncrement) {
        if (!f.type.startsWith('int')) {
          throw Exception('Auto increment is allowed only on int columns!');
        }
        _write(", autoIncrement: ${f.autoIncrement}");
      }

      if (f.length != null) {
        if (!f.type.startsWith('String')) {
          throw Exception('Length is allowed only on text columns!');
        }
        _write(", length: ${f.length}");
      }

      _write(', isNullable: ${f.isNullable}');

      if (f.unique != null) _write(', uniqueGroup: "${f.unique}"');

      _writeln(');');
    }
    _writeln('return adapter.createTable(st);');
    _w.writeln('}');
  }

  void _writeToSetColumns() {
    _w.writeln(
        'List<SetColumn> toSetColumns(${_b.modelType} model, {bool update = false, Set<String>? only, bool onlyNonNull = false}) {');
    _w.writeln('List<SetColumn> ret = [];');
    _w.writeln();

    _w.writeln('if(only == null && !onlyNonNull) {');

    // TODO if update, don't set primary key
    _b.fields.values.forEach((Field field) {
      if (field.autoIncrement) {
        _w.writeln("if(model.${field.field} != null) {");
      }
      _w.writeln("ret.add(${field.field}.set(model.${field.field}));");
      if (field.autoIncrement) {
        _w.writeln("}");
      }
    });

    _w.writeln('} else if (only != null) {');

    // TODO if update, don't set primary key
    _b.fields.values.forEach((Field field) {
      if (field.autoIncrement) {
        _w.writeln("if(model.${field.field} != null) {");
      }
      _w.writeln(
          "if(only.contains(${field.field}.name)) ret.add(${field.field}.set(model.${field.field}));");
      if (field.autoIncrement) {
        _w.writeln("}");
      }
    });

    _w.writeln('} else /* if (onlyNonNull) */ {');

    // TODO if update, don't set primary key
    _b.fields.values.forEach((Field field) {
      // _w.writeln("if(model.${field.field} != null) {");
      _w.writeln("ret.add(${field.field}.set(model.${field.field}));");
      // _w.writeln("}");
    });

    _w.writeln('}');

    _w.writeln();
    _w.writeln('return ret;');
    _w.writeln('}');
  }

  void _writeCrud() {
    _writeInsert();
    _writeInsertMany();
    _writeUpsert();
    _writeUpsertMany();
    _writeUpdate();
    _writeUpdateMany();
    _writeFind();
    _writeRemove();
    _writeRemoveMany();
  }

  void _writeUpsert() {
    if (_b.preloads.isEmpty && !_b.primary.any((f) => f.autoIncrement)) {
      _w.writeln(
          'Future<dynamic> upsert(${_b.modelType} model, {bool cascade = false, Set<String>? only, bool onlyNonNull = false, isForeignKeyEnabled = false}) async {');
      _w.write('final Upsert upsert = upserter');
      _w.writeln(
          '.setMany(toSetColumns(model, only: only, onlyNonNull: onlyNonNull));');
      _w.writeln('return adapter.upsert(upsert);');
      _w.writeln('}');
      return;
    }

    _w.writeln(
        'Future<dynamic> upsert(${_b.modelType} model, {bool cascade = false, Set<String>? only, bool onlyNonNull = false, isForeignKeyEnabled = false}) async {');

    _w.writeln('var retId;');
    _w.writeln('if (isForeignKeyEnabled) {');
    _w.write('final Insert insert = Insert(tableName, ignoreIfExist: true)');
    _w.writeln(
        '.setMany(toSetColumns(model, only: only, onlyNonNull: onlyNonNull));');
    _w.writeln('retId = await adapter.insert(insert);');
    _w.writeln('if (retId == null) {');
    _w.write('final Update update = updater.');
    final String wheres = _b.primary
        .map((Field f) =>
            'where(this.${f.field}.eq(model.${f.field}${f.type.endsWith('?') ? '!' : ''}))')
        .join('.');
    _w.write(wheres);
    _w.write(
        '.setMany(toSetColumns(model, only: only, onlyNonNull: onlyNonNull));');
    _w.writeln('retId = adapter.update(update);');

    _w.writeln('}');

    _w.writeln('} else {');
    _w.write('final Upsert upsert = upserter');
    _w.write(
        '.setMany(toSetColumns(model, only: only, onlyNonNull: onlyNonNull))');
    for (Field f in _b.primary) {
      if (f.autoIncrement) _w.write('.id(${f.field}.name)');
    }
    _w.writeln(';');
    _w.writeln('retId = await adapter.upsert(upsert);');
    _w.writeln('}');

    _w.writeln('if(cascade) {');
    _w.writeln('${_b.modelType}? newModel;');
    for (Preload p in _b.preloads) {
      _w.writeln('if(model.${p.property} != null) {');
      _w.writeln('newModel ??= await find(');
      _write(_b.primary.map((f) {
        if (f.autoIncrement) return 'retId';
        return 'model.${f.field}';
      }).join(','));
      _writeln(');');

      if (!p.hasMany) {
        _write(_uncap(p.beanInstanceName));
        _writeln(
            '.associate${_b.modelType}(model.' + p.property + '!, newModel!);');
        _write('await ' +
            _uncap(p.beanInstanceName) +
            '.upsert(model.' +
            p.property +
            '!, cascade: cascade);');
      } else {
        if (p is PreloadOneToX) {
          _write('model.' + p.property + '!.forEach((x) => ');
          _write(_uncap(p.beanInstanceName));
          _writeln('.associate${_b.modelType}(x, newModel!));');
          _writeln('for(final child in model.${p.property}!) {');
          _writeln('await ' +
              _uncap(p.beanInstanceName) +
              '.upsert(child, cascade: cascade);');
          _writeln('}');
        } else if (p is PreloadManyToMany) {
          _writeln('for(final child in model.${p.property}!) {');
          _writeln(
              'await ${p.targetBeanInstanceName}.upsert(child, cascade: cascade);');
          if (_b.modelType.compareTo(
                  p.targetInfo == null ? '' : p.targetInfo!.modelType) >
              0) {
            _writeln(
                'await ${p.beanInstanceName}.attach(newModel, child, upsert: true);');
          } else {
            _writeln(
                'await ${p.beanInstanceName}.attach(child, newModel, upsert: true);');
          }
          _writeln('}');
        }
      }
      _w.writeln('}');
    }
    _w.writeln('}');
    _w.writeln('return retId;');
    _w.writeln('}');
  }

  void _writeUpsertMany() {
    var cascade = '';
    if (_b.preloads.length > 0) {
      cascade = 'bool cascade = false, ';
    }
    _w.writeln(
        'Future<void> upsertMany(List<${_b.modelType}> models, {${cascade} bool onlyNonNull = false, Set<String>? only, isForeignKeyEnabled = false}) async {');
    if (cascade.isNotEmpty) {
      _w.write('if(cascade || isForeignKeyEnabled)  {');
      _w.write('final List<Future> futures = [];');
      _w.write('for (var model in models) {');
      _w.write(
          'futures.add(upsert(model, cascade: cascade, isForeignKeyEnabled: isForeignKeyEnabled));');
      _w.write('}');
      _w.writeln('await Future.wait(futures);');
      _w.writeln('return;');
      _w.write('}');
      _w.write('else {');
    }

    _w.write('final List<List<SetColumn>> data = [];');
    _w.write('for (var i = 0; i < models.length; ++i) {');
    _w.write('var model = models[i];');
    _w.write(
        'data.add(toSetColumns(model, only: only, onlyNonNull: onlyNonNull).toList());');

    _w.write('}');
    _w.write('final UpsertMany upsert = upserters.addAll(data);');
    _w.writeln('await adapter.upsertMany(upsert);');
    _w.writeln('return;');

    if (cascade.isNotEmpty) {
      _w.writeln('}');
    }

    _w.writeln('}');
  }

  void _writeInsert() {
    if (_b.preloads.isEmpty && !_b.primary.any((f) => f.autoIncrement)) {
      _w.writeln(
          'Future<dynamic> insert(${_b.modelType} model, {bool cascade = false, bool onlyNonNull = false, Set<String>? only}) async {');
      _w.write('final Insert insert = inserter');
      _w.writeln(
          '.setMany(toSetColumns(model, only: only, onlyNonNull: onlyNonNull));');
      _w.writeln('return adapter.insert(insert);');
      _w.writeln('}');
      return;
    }

    _w.writeln(
        'Future<dynamic> insert(${_b.modelType} model, {bool cascade = false, bool onlyNonNull = false, Set<String>? only}) async {');
    _w.write('final Insert insert = inserter');
    _w.write(
        '.setMany(toSetColumns(model, only: only, onlyNonNull: onlyNonNull))');
    for (Field f in _b.primary) {
      if (f.autoIncrement) _w.write('.id(${f.field}.name)');
    }
    _w.writeln(';');
    _w.writeln('var retId = await adapter.insert(insert);');

    _w.writeln('if(cascade) {');
    _w.writeln('${_b.modelType}? newModel;');
    for (Preload p in _b.preloads) {
      _w.writeln('if(model.${p.property} != null) {');
      _w.writeln('newModel ??= await find(');
      _write(_b.primary.map((f) {
        if (f.autoIncrement) return 'retId';
        return 'model.${f.field}';
      }).join(','));
      _writeln(');');

      if (!p.hasMany) {
        _write(_uncap(p.beanInstanceName));
        _writeln(
            '.associate${_b.modelType}(model.' + p.property + '!, newModel!);');
        _write('await ' +
            _uncap(p.beanInstanceName) +
            '.insert(model.' +
            p.property +
            '!, cascade: cascade);');
      } else {
        if (p is PreloadOneToX) {
          _write('model.' + p.property + '!.forEach((x) => ');
          _write(_uncap(p.beanInstanceName));
          _writeln('.associate${_b.modelType}(x, newModel!));');
          _writeln('for(final child in model.${p.property}!) {');
          _writeln('await ' +
              _uncap(p.beanInstanceName) +
              '.insert(child, cascade: cascade);');
          _writeln('}');
        } else if (p is PreloadManyToMany) {
          _writeln('for(final child in model.${p.property}!) {');
          _writeln(
              'await ${p.targetBeanInstanceName}.insert(child, cascade: cascade);');
          if (_b.modelType.compareTo(
                  p.targetInfo == null ? '' : p.targetInfo!.modelType) >
              0) {
            _writeln('await ${p.beanInstanceName}.attach(newModel, child);');
          } else {
            _writeln('await ${p.beanInstanceName}.attach(child, newModel);');
          }
          _writeln('}');
        }
      }
      _w.writeln('}');
    }
    _w.writeln('}');
    _w.writeln('return retId;');
    _w.writeln('}');
  }

  void _writeInsertMany() {
    var cascade = '';
    if (_b.preloads.length > 0) {
      cascade = 'bool cascade = false,';
    }
    _w.writeln(
        'Future<void> insertMany(List<${_b.modelType}> models, {${cascade}bool onlyNonNull = false, Set<String>? only}) async {');
    if (cascade.isNotEmpty) {
      _w.write('if(cascade)  {');
      _w.write('final List<Future> futures = [];');
      _w.write('for (var model in models) {');
      _w.write('futures.add(insert(model, cascade: cascade));');
      _w.write('}');
      _w.writeln('await Future.wait(futures);');
      _w.writeln('return;');
      _w.write('}');
      _w.write('else {');
    }

    _w.write(
        'final List<List<SetColumn>> data = models.map((model) => toSetColumns(model, only: only, onlyNonNull: onlyNonNull)).toList();');
    _w.writeln('final InsertMany insert = inserters.addAll(data);');
    _w.writeln('await adapter.insertMany(insert);');
    _w.writeln('return;');

    if (cascade.isNotEmpty) {
      _w.writeln('}');
    }

    _w.writeln('}');
  }

  void _writeUpdate() {
    if (_b.primary.length == 0) return;

    if (_b.preloads.length == 0) {
      _w.writeln(
          'Future<int> update(${_b.modelType} model, {bool cascade = false, bool associate = false, Set<String>? only, bool onlyNonNull = false}) async {');
      _w.write('final Update update = updater.');
      final String wheres = _b.primary
          .map((Field f) =>
              'where(this.${f.field}.eq(model.${f.field}${f.type.endsWith('?') ? '!' : ''}))')
          .join('.');
      _w.write(wheres);
      _w.writeln(
          '.setMany(toSetColumns(model, only: only, onlyNonNull: onlyNonNull));');
      _w.writeln('return adapter.update(update);');
      _w.writeln('}');
      return;
    }

    _w.writeln(
        'Future<int> update(${_b.modelType} model, {bool cascade = false, bool associate = false, Set<String>? only, bool onlyNonNull = false}) async {');
    _w.write('final Update update = updater.');
    final String wheres = _b.primary
        .map((Field f) =>
            'where(this.${f.field}.eq(model.${f.field}${f.type.endsWith('?') ? '!' : ''}))')
        .join('.');
    _w.write(wheres);
    _w.writeln(
        '.setMany(toSetColumns(model, only: only, onlyNonNull: onlyNonNull));');
    _w.writeln('final ret = adapter.update(update);');

    _w.writeln('if(cascade) {');
    _w.writeln('${_b.modelType}? newModel;');
    for (Preload p in _b.preloads) {
      _w.writeln('if(model.${p.property} != null) {');
      if (p is PreloadOneToX) {
        _writeln('if(associate) {');
        _w.writeln('newModel ??= await find(');
        _write(_b.primary.map((f) {
          return 'model.${f.field}';
        }).join(','));
        _writeln(');');

        if (!p.hasMany) {
          _write(_uncap(p.beanInstanceName));
          _writeln('.associate${_b.modelType}(model.' +
              p.property +
              '!, newModel!);');
        } else {
          _write('model.' + p.property + '!.forEach((x) => ');
          _write(_uncap(p.beanInstanceName));
          _writeln('.associate${_b.modelType}(x, newModel!));');
        }
        _writeln('}');
      }

      if (!p.hasMany) {
        _write('await ' +
            _uncap(p.beanInstanceName) +
            '.update(model.' +
            p.property +
            '!, cascade: cascade, associate: associate);');
      } else {
        _writeln('for(final child in model.${p.property}!) {');
        if (p is PreloadOneToX) {
          _writeln('await ' +
              _uncap(p.beanInstanceName) +
              '.update(child, cascade: cascade, associate: associate);');
        } else if (p is PreloadManyToMany) {
          _writeln(
              'await ${p.targetBeanInstanceName}.update(child, cascade: cascade, associate: associate);');
        }
        _writeln('}');
      }
      _w.writeln('}');
    }
    _w.writeln('}');

    _w.writeln('return ret;');
    _w.writeln('}');
  }

  void _writeUpdateMany() {
    var cascade = '';
    if (_b.preloads.length > 0) {
      cascade = 'bool cascade = false, ';
    }
    _w.writeln(
        'Future<void> updateMany(List<${_b.modelType}> models, {${cascade} bool onlyNonNull = false, Set<String>? only}) async {');
    if (cascade.isNotEmpty) {
      _w.write('if(cascade)  {');
      _w.write('final List<Future> futures = [];');
      _w.write('for (var model in models) {');
      _w.write('futures.add(update(model, cascade: cascade));');
      _w.write('}');
      _w.writeln('await Future.wait(futures);');
      _w.writeln('return;');
      _w.write('}');
      _w.write('else {');
    }

    _w.write('final List<List<SetColumn>> data = [];');
    _w.write('final List<Expression> where = [];');
    _w.write('for (var i = 0; i < models.length; ++i) {');
    _w.write('var model = models[i];');
    _w.write(
        'data.add(toSetColumns(model, only: only, onlyNonNull: onlyNonNull).toList());');

    String? wheres;
    for (var prim in _b.primary) {
      if (wheres == null) {
        wheres =
            'this.${prim.field}.eq(model.${prim.field}${prim.type.endsWith('?') ? '!' : ''})';
      } else {
        wheres =
            '$wheres.and(this.${prim.field}.eq(model.${prim.field}${prim.type.endsWith('?') ? '!' : ''}))';
      }
    }
    _w.write('where.add($wheres);');
    _w.write('}');
    _w.write('final UpdateMany update = updaters.addAll(data, where);');
    _w.writeln('await adapter.updateMany(update);');
    _w.writeln('return;');

    if (cascade.isNotEmpty) {
      _w.writeln('}');
    }

    _w.writeln('}');
  }

  void _writeFind() {
    if (_b.primary.length == 0) return;

    _write('Future<${_b.modelType}?> find(');
    final String args =
        _b.primary.map((Field f) => '${f.type} ${f.field}').join(',');
    _write(args);
    _write(', {bool preload = false, bool cascade = false}');
    _writeln(') async {');
    _writeln('final Find find = finder.');
    final String wheres = _b.primary
        .map((Field f) =>
            'where(this.${f.field}.eq(${f.field}${f.type.endsWith('?') ? '!' : ''}))')
        .join('.');
    _write(wheres);
    _writeln(';');

    if (_b.preloads.length > 0) {
      _writeln('final ${_b.modelType}? model = await findOne(find);');
      _writeln('if (preload && model != null) {');
      _writeln('await this.preload(model, cascade: cascade);');
      _writeln('}');
      _writeln('return model;');
    } else {
      _writeln('return await findOne(find);');
    }
    _writeln('}');
  }

  void _writeRemove() {
    if (_b.primary.length == 0) return;

    if (_b.preloads.length == 0) {
      _w.writeln('Future<int> remove(');
      final String args =
          _b.primary.map((Field f) => '${f.type} ${f.field}').join(',');
      _w.write(args);
      _w.writeln(') async {');
      _w.writeln('final Remove remove = remover.');
      final String wheres = _b.primary
          .map((Field f) =>
              'where(this.${f.field}.eq(${f.field}${f.type.endsWith('?') ? '!' : ''}))')
          .join('.');
      _w.write(wheres);
      _w.writeln(';');
      _w.writeln('return adapter.remove(remove);');
      _w.writeln('}');
      return;
    }

    _w.writeln('Future<int> remove(');
    final String args =
        _b.primary.map((Field f) => '${f.type} ${f.field}').join(',');
    _w.write(args);
    _w.writeln(', {bool cascade = false}) async {');

    _writeln('if (cascade) {');
    _w.writeln('final ${_b.modelType}? newModel = ');
    _w.writeln('await find(');
    _write(_b.primary.map((f) {
      return '${f.field}';
    }).join(','));
    _writeln(');');
    _w.writeln('if(newModel != null) {');
    for (Preload p in _b.preloads) {
      if (p is PreloadOneToX) {
        _write(
            'await ' + p.beanInstanceName + '.removeBy' + _b.modelType + '(');
        _write(p.fields
            .map((f) => 'newModel.${f.field}${f.type.endsWith('?') ? '!' : ''}')
            .join(', '));
        _writeln(');');
      } else if (p is PreloadManyToMany) {
        _write('await ${p.beanInstanceName}.detach${_b.modelType}(newModel);');
      }
    }
    _w.writeln('}');
    _writeln('}');

    _w.writeln('final Remove remove = remover.');
    final String wheres = _b.primary
        .map((Field f) =>
            'where(this.${f.field}.eq(${f.field}${f.type.endsWith('?') ? '!' : ''}))')
        .join('.');
    _w.write(wheres);
    _w.writeln(';');
    _w.writeln('return adapter.remove(remove);');
    _w.writeln('}');
  }

  void _writeFindOneByBeanedAssociation(BeanedAssociation m) {
    if (!(m.byHasMany ?? false)) {
      _w.write('Future<${_b.modelType}?>');
    } else {
      _w.write('Future<List<${_b.modelType}>>');
    }
    _w.write(' findBy${_cap(m.modelName)}(');
    final String args =
        m.fields.map((Field f) => '${f.type} ${f.field}').join(',');
    _w.write(args);
    _write(', {bool preload = false, bool cascade = false}');
    _w.writeln(') async {');

    _w.writeln('final Find find = finder.');
    final String wheres = m.fields
        .map((Field f) =>
            'where(this.${f.field}.eq(${f.field}${f.type.endsWith('?') ? '!' : ''}))')
        .join('.');
    _w.write(wheres);
    _w.writeln(';');

    if (_b.preloads.length > 0) {
      if (!(m.byHasMany ?? false)) {
        _write('final ${_b.modelType}? model = await ');
        _writeln('findOne(find);');

        _writeln('if (preload && model != null) {');
        _writeln('await this.preload(model, cascade: cascade);');
        _writeln('}');

        _writeln('return model;');
      } else {
        _write('final List<${_b.modelType}> models = ');
        _writeln('await findMany(find);');

        _writeln('if (preload) {');
        _writeln('await this.preloadAll(models, cascade: cascade);');
        _writeln('}');

        _writeln('return models;');
      }
    } else {
      _write('return ');
      if (!(m.byHasMany ?? false)) {
        _writeln('findOne(find);');
      } else {
        _writeln('findMany(find);');
      }
    }

    _w.writeln('}');
  }

  void _writeRemoveMany() {
    if (_b.primary.length == 0) return;

    _w.writeln('Future<int> removeMany(List<${_b.modelType}>? models) async {');
    // Return if models is empty. If this is not done, all records will be removed!
    _w.writeln(
        "// Return if models is empty. If this is not done, all records will be removed! ");
    _w.writeln("if(models == null || models.isEmpty) return 0;");
    _w.writeln('final Remove remove = remover;');
    _writeln('for(final model in models) {');
    _write('remove.or(');
    final String wheres = _b.primary
        .map((Field f) =>
            'this.${f.field}.eq(model.${f.field}${f.type.endsWith('?') ? '!' : ''})')
        .join('|');
    _w.write(wheres);
    _writeln(');');
    _w.writeln('}');
    _w.writeln('return adapter.remove(remove);');
    _w.writeln('}');
    return;
  }

  void _removeByForeign(BelongsToAssociation m) {
    _w.write('Future<int>');
    _w.write(' removeBy${_cap(m.modelName)}(');
    final String args =
        m.fields.map((Field f) => '${f.type} ${f.field}').join(',');
    _w.write(args);
    _w.writeln(') async {');

    _w.writeln('final Remove rm = remover.');
    final String wheres = m.fields
        .map((Field f) => 'where(this.${f.field}.eq(${f.field}${f.type.endsWith('?') ? '!' : ''}))')
        .join('.');
    _w.write(wheres);
    _w.writeln(';');

    _write('return await adapter.remove(rm);');
    _w.writeln('}');
  }

  void _writeFindListByBeanedAssociationList(BeanedAssociation m) {
    _write('Future<List<${_b.modelType}>> findBy${_cap(m.modelName)}List(');
    _write('List<${m.modelName}>? models');
    _write(', {bool preload = false, bool cascade = false}');
    _writeln(') async {');
    // Return if models is empty. If this is not done, all the records will be returned!
    _writeln(
        "// Return if models is empty. If this is not done, all the records will be returned!");
    _writeln("if(models == null || models.isEmpty) return [];");
    _writeln('final Find find = finder;');
    _writeln('for (${m.modelName} model in models) {');
    _write('find.or(');
    final wheres = <String>[];
    for (int i = 0; i < m.fields.length; i++) {
      wheres.add(
          'this.${m.fields[i].field}.eq(model.${m.foreignFields[i].field}${m.foreignFields[i].type.endsWith('?') ? '!' : ''})');
    }
    _w.write(wheres.join(' & '));
    _writeln(');');
    _writeln('}');

    if (_b.preloads.length > 0) {
      _writeln('final List<${_b.modelType}> retModels = await findMany(find);');
      _writeln('if (preload) {');
      _writeln('await this.preloadAll(retModels, cascade: cascade);');
      _writeln('}');
      _writeln('return retModels;');
    } else {
      _writeln('return findMany(find);');
    }

    _w.writeln('}');
  }

  void _writePreload() {
    if (_b.preloads.length == 0) return;

    _writeln(
        'Future<${_b.modelType}> preload(${_b.modelType} model, {bool cascade = false}) async {');
    for (Preload p in _b.preloads) {
      _write('model.');
      _write(p.property);
      _write(' = await ');

      if (p is PreloadOneToX) {
        _write(_uncap(p.beanInstanceName));
        _write('.findBy');
        _write(_b.modelType);
        _write('(');
        final String args = p.foreignFields
            .map((Field f) => f.foreign!.refCol)
            .map(_b.fieldByColName)
            .map((Field? f) => 'model.${f!.field}${f.type.endsWith('?') ? '!' : ''}')
            .join(',');
        _write(args);
        _write(', preload: cascade, cascade: cascade');
        _writeln(');');
      } else if (p is PreloadManyToMany) {
        _write('${p.beanInstanceName}.fetchBy${_b.modelType}(model);');
      }
    }
    _writeln('return model;');
    _writeln('}');
  }

  void _writePreloadAll() {
    if (_b.preloads.length == 0) return;

    _writeln(
        'Future<List<${_b.modelType}>> preloadAll(List<${_b.modelType}> models, {bool cascade = false}) async {');
    for (Preload p in _b.preloads) {
      if (p is PreloadOneToX) {
        if (p.hasMany) {
          _writeln(
              'models.forEach((${_b.modelType} model) => model.${p.property} ??= []);');
        }

        _write('await OneToXHelper.');
        // Arg1: models
        _write('preloadAll<${_b.modelType}, ${p.modelName}>(models, ');
        // Arg2: ParentGetter
        _write('(${_b.modelType} model) => [');
        {
          final String args = p.foreignFields
              .map((Field f) => f.foreign!.refCol)
              .map(_b.fieldByColName)
              .map((Field? f) => 'model.${f!.field}')
              .join(',');
          _write(args);
        }
        _write('], ');
        //Arg3: function
        _write(_uncap(p.beanInstanceName));
        _write('.findBy');
        _write(_b.modelType);
        _write('List, ');
        //Arg4: ChildGetter
        _write('(${p.modelName} model) => [');
        {
          final String args =
              p.foreignFields.map((Field f) => 'model.${f.field}').join(',');
          _write(args);
        }
        _write('], ');
        //Arg5: Setter
        if (!p.hasMany) {
          _write(
              '(${_b.modelType} model, ${p.modelName} child) => model.${p.property} = child, ');
        } else {
          _write(
              '(${_b.modelType} model, ${p.modelName} child) => model.${p.property} = List.from(model.${p.property}!)..add(child), ');
        }
        _writeln('cascade: cascade);');
      } else if (p is PreloadManyToMany) {
        _writeln('for(${_b.modelType} model in models) {');
        _writeln(
            'var temp = await ${p.beanInstanceName}.fetchBy${_b.modelType}(model);');
        _writeln('if(model.${p.property} == null) model.${p.property} = temp;');
        _writeln('else {');
        _writeln('model.${p.property}.clear();');
        _writeln('model.${p.property}.addAll(temp);');
        _writeln('}');
        _writeln('}');
      }
    }
    _writeln('return models;');
    _writeln('}');
  }

  void _writeBeans() {
    final written = Set<String>();

    for (Preload p in _b.preloads) {
      if (written.contains(p.beanInstanceName)) continue;
      written.add(p.beanInstanceName);

      _write(p.beanName);
      _write(' get ');
      _write(p.beanInstanceName);
      _writeln(';');
      if (p is PreloadManyToMany) {
        if (written.contains(p.targetBeanInstanceName)) continue;
        written.add(p.targetBeanInstanceName);

        _writeln('');
        _write(p.targetBeanName);
        _write(' get ');
        _write(p.targetBeanInstanceName);
        _writeln(';');
      }
    }

    for (BelongsToAssociation f in _b.belongTos.values) {
      if (f.belongsToMany) {
        if (written.contains(f.beanInstanceName)) continue;
        written.add(f.beanInstanceName);

        _write(f.beanName);
        _write(' get ');
        _write(f.beanInstanceName);
        _writeln(';');
      }
    }

    for (Field f in _b.fields.values) {
      if (f.foreign is BelongsToForeign) {
        BelongsToForeign fb = f.foreign as BelongsToForeign;
        if (written.contains(fb.beanInstanceName)) continue;
        written.add(fb.beanInstanceName);

        _write(fb.beanName);
        _write(' get ');
        _write(fb.beanInstanceName);
        _writeln(';');
      }
    }
  }

  void _writeAssociate(BelongsToAssociation m) {
    _write('void associate${_cap(m.modelName)}(');
    _write('${_b.modelType} child, ');
    _write('${m.modelName} parent');
    _writeln(') {');

    for (int i = 0; i < m.fields.length; i++) {
      _writeln(
          'child.${m.fields[i].field} = parent.${m.foreignFields[i].field}${m.foreignFields[i].type.endsWith('?') ? '!' : ''};');
    }

    _writeln('}');
  }

  void _writeDetach(BelongsToAssociation m) {
    _writeln(
        'Future<int> detach${_cap(m.modelName)}(${_cap(m.modelName)} model) async {');
    _write('final dels = await findBy${_cap(m.modelName)}(');
    _write(m.foreignFields.map((f) => 'model.' + f.field).join(', '));
    _writeln(');');
    _writeln('if(dels.isNotEmpty) {');
    _write('await removeBy${_cap(m.modelName)}(');
    _write(m.foreignFields.map((f) => 'model.' + f.field).join(', '));
    _writeln(');');
    final String beanName =
        (m.other as PreloadManyToMany).targetBeanInstanceName;
    _writeln('final exp = Or();');
    _writeln('for(final t in dels) {');
    _write('exp.or(');
    BelongsToAssociation? o = _b.getMatchingManyToMany(m);
    if (o != null) {
      for (int i = 0; i < o.fields.length; i++) {
        _write(
            '$beanName.${o.foreignFields[i].field}.eq(t.${o.fields[i].field})');
        if (i < o.fields.length - 1) {
          _write('&');
        }
      }
    }
    _writeln(');');
    _writeln('}');

    _write('return await $beanName.removeWhere(exp);');
    _writeln('}');
    _writeln('return 0;');
    _writeln('}');
  }

  void _writeFetchOther(BelongsToAssociation m) {
    final String beanName =
        (m.other as PreloadManyToMany).targetBeanInstanceName;
    final String targetModel = (m.other as PreloadManyToMany).targetModelName;
    _writeln(
        'Future<List<$targetModel>> fetchBy${_cap(m.modelName)}(${_cap(m.modelName)} model) async {');
    _write('final pivots = await findBy${_cap(m.modelName)}(');
    _write(m.foreignFields.map((f) => 'model.' + f.field).join(', '));
    _writeln(');');
    // Return if model has no pivots. If this is not done, all records will be removed!
    _writeln(
        "// Return if model has no pivots. If this is not done, all records will be removed!");
    _writeln('if (pivots.isEmpty) return [];');
    _writeln('final exp = Or();');
    _writeln('for(final t in pivots) {');
    _write('exp.or(');
    BelongsToAssociation? o = _b.getMatchingManyToMany(m);
    if (o != null) {
      for (int i = 0; i < o.fields.length; i++) {
        _write(
            '$beanName.${o.foreignFields[i].field}.eq(t.${o.fields[i].field}${o.fields[i].type.endsWith('?') ? '!' : ''})');
        if (i < o.fields.length - 1) {
          _write('&');
        }
      }
    }
    _writeln(');');
    _writeln('}');

    _write('return await $beanName.findWhere(exp);');
    _writeln('}');
  }

  void _writeAttach() {
    final BelongsToAssociation? m = _b.belongTos.values.firstWhereOrNull(
        (BelongsToAssociation f) =>
            f is BelongsToAssociation && f.belongsToMany);
    if (m == null) return;

    final BelongsToAssociation? m1 = _b.getMatchingManyToMany(m);
    if (m1 != null) {
      _writeln('Future<dynamic> attach(');
      if (m.modelName.compareTo(m1.modelName) > 0) {
        _write('${m.modelName} one, ${m1.modelName} two');
      } else {
        _write('${m1.modelName} one, ${_cap(m.modelName)} two');
      }
      _writeln(', {bool upsert = false}) async {');
      _writeln('final ret = ${_b.modelType}();');

      if (m.modelName.compareTo(m1.modelName) > 0) {
        for (int i = 0; i < m.fields.length; i++) {
          _writeln(
              'ret.${m.fields[i].field} = one.${m.foreignFields[i].field};');
        }
        for (int i = 0; i < m1.fields.length; i++) {
          _writeln(
              'ret.${m1.fields[i].field} = two.${m1.foreignFields[i].field};');
        }
      } else {
        for (int i = 0; i < m1.fields.length; i++) {
          _writeln(
              'ret.${m1.fields[i].field} = one.${m1.foreignFields[i].field};');
        }
        for (int i = 0; i < m.fields.length; i++) {
          _writeln(
              'ret.${m.fields[i].field} = two.${m.foreignFields[i].field};');
        }
      }
    }
    _writeln('''
    if(!upsert) {
      return insert(ret);
    } else {
      return this.upsert(ret);
    }
    ''');
    _writeln('}');
  }

  void _write(String str) => _w.write(str);

  void _writeln(String str) => _w.writeln(str);

  String toString() => _w.toString();
}

String _cap(String str) => str.substring(0, 1).toUpperCase() + str.substring(1);

String _uncap(String str) =>
    str.substring(0, 1).toLowerCase() + str.substring(1);

String _camToSnak(String str) {
  final sb = StringBuffer();

  for (int i = 0; i < str.length; i++) {
    final int code = str.codeUnitAt(i);
    if (code >= 65 && code <= 90) {
      sb.write('_');
    }
    sb.writeCharCode(code);
  }

  return sb.toString().toLowerCase();
}
