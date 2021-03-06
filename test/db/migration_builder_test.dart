import 'dart:async';
import 'dart:isolate';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Create table", () async {
    var expectedSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'"),
        new SchemaColumn.relationship(
            "ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz",
            relatedTableName: "abc",
            rule: ManagedRelationshipDeleteRule.cascade)
      ]),
      new SchemaTable("abc", [
        new SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)
      ])
    ]);

    await expectSchema(new Schema.empty(),
        becomesSchema: expectedSchema);
  });

  test("Delete table", () async {
    await expectSchema(new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
      ]),
      new SchemaTable("donotdelete", [])
    ]), becomesSchema: new Schema([
      new SchemaTable("donotdelete", [])
    ]));
  });

  test("Add column", () async {
    var existingSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
      ])
    ]);

    var expectedSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'"),
        new SchemaColumn.relationship(
            "ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz",
            relatedTableName: "abc",
            rule: ManagedRelationshipDeleteRule.cascade)
      ]),
      new SchemaTable("abc", [
        new SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)
      ])
    ]);

    await expectSchema(existingSchema,
        becomesSchema: expectedSchema);
  });

  test("Delete column", () async {
    var existingSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'"),
        new SchemaColumn.relationship(
            "ref", ManagedPropertyType.bigInteger, relatedColumnName: "xyz",
            relatedTableName: "abc",
            rule: ManagedRelationshipDeleteRule.cascade)
      ]),
      new SchemaTable("abc", [
        new SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)
      ])
    ]);
    var expectedSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: "'foo'")
      ]),
      new SchemaTable("abc", [
        new SchemaColumn("xyz", ManagedPropertyType.bigInteger, isPrimaryKey: true)
      ])
    ]);

    await expectSchema(existingSchema,
        becomesSchema: expectedSchema);
  });

  test("Alter column, many statements", () async {
    var existingSchema = new Schema([
      new SchemaTable("foo", [
        new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("loaded", ManagedPropertyType.string,
            isIndexed: true,
            isNullable: true,
            autoincrement: true,
            isUnique: true,
            defaultValue: null)
      ])
    ]);
    var expectedSchema = new Schema.from(existingSchema);
    expectedSchema.tableForName("foo").columnForName("loaded")
      ..isIndexed = false
      ..isNullable = false
      ..isUnique = false
      ..defaultValue = "'foo'";

    await expectSchema(existingSchema,
        becomesSchema: expectedSchema);
  });

  test("Alter column, just one statement", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("loaded", ManagedPropertyType.string,
          isIndexed: true,
          isNullable: true,
          autoincrement: true,
          isUnique: true,
          defaultValue: "'foo'")
    ]);
    var alteredColumn = new SchemaColumn.from(
        existingTable.columnForName("loaded"))
      ..isIndexed = false;

    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      alteredColumn
    ]);

    await expectSchema(new Schema([existingTable]),
        becomesSchema: new Schema([expectedTable]));
  });

  test("Create table with uniqueSet", () async {
    var expectedTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSetNames: ["a", "b"]);

    await expectSchema(new Schema.empty(),
        becomesSchema: new Schema([
          expectedTable
        ]));
  });

  test("Alter table to add uniqueSet", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["a", "b"];

    await expectSchema(new Schema([existingTable]),
        becomesSchema: new Schema([alteredTable]));
  });

  test("Alter table to remove uniqueSet", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
    ], uniqueColumnSetNames: ["a", "b"]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = null;

    await expectSchema(new Schema([existingTable]),
        becomesSchema: new Schema([alteredTable]));
  });

  test("Alter table to modify uniqueSet (same number of keys)", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
      new SchemaColumn("c", ManagedPropertyType.string),
    ], uniqueColumnSetNames: ["a", "b"]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["b", "c"];

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([
      alteredTable
    ]));
  });

  test("Alter table to modify uniqueSet (different number of keys)", () async {
    var existingTable = new SchemaTable("foo", [
      new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
      new SchemaColumn("a", ManagedPropertyType.string),
      new SchemaColumn("b", ManagedPropertyType.string),
      new SchemaColumn("c", ManagedPropertyType.string),
    ], uniqueColumnSetNames: ["a", "b"]);

    var alteredTable = new SchemaTable.from(existingTable)
      ..uniqueColumnSet = ["a", "b", "c"];

    await expectSchema(new Schema([existingTable]), becomesSchema: new Schema([
      alteredTable
    ]));
  });
}


String sourceForSchemaUpgrade(String migrationSource) {
  return """
$migrationSource

Future main(List<String> args, Map<String, dynamic> message) async {
  var sendPort = message['sendPort'];
  var schema = message['schema'];
  var database = new SchemaBuilder(null, new Schema.fromMap(schema));
  var migration = new Migration1()..database = database;
  await migration.upgrade();
  sendPort.send(database.schema.asMap());
}  


  """;
}

Future<Map<String, dynamic>> runSource(String source, Schema fromSchema) async {
  var dataUri = Uri.parse(
      "data:application/dart;charset=utf-8,${Uri.encodeComponent(source)}");
  var completer = new Completer<Map>();
  var receivePort = new ReceivePort();
  receivePort.listen((msg) {
    completer.complete(msg);
  });

  var errPort = new ReceivePort()
    ..listen((msg) {
      throw new Exception(msg);
    });

  await Isolate.spawnUri(dataUri, [], {
    "sendPort": receivePort.sendPort,
    "schema": fromSchema.asMap()
  },
      onError: errPort.sendPort,
      packageConfig: new Uri.file(".packages"));

  var results = await completer.future;
  receivePort.close();
  errPort.close();
  return results;
}

Future expectSchema(Schema schema,
    {Schema becomesSchema, List<String> afterCommands, void alsoVerify(Schema createdSchema)}) async {
  var migrationSource = MigrationBuilder.sourceForSchemaUpgrade(schema, becomesSchema, 1);

  var scriptSource = sourceForSchemaUpgrade(migrationSource);
  var response = await runSource(scriptSource, schema);
  var createdSchema = new Schema.fromMap(response);
  var diff = createdSchema.differenceFrom(becomesSchema);

  expect(diff.hasDifferences, false);

  if (alsoVerify != null) {
    alsoVerify(createdSchema);
  }
}