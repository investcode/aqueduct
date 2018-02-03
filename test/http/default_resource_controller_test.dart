import 'dart:async';

import 'package:aqueduct/test.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import '../helpers.dart';

void main() {
  group("Standard operations", () {
    var app = new Application<TestChannel>();
    Controller.letUncaughtExceptionsEscape = true;
    app.options.port = 8888;
    var client = new TestClient.onPort(app.options.port);
    List<TestModel> allObjects = [];

    setUpAll(() async {
      await app.test();

      var now = new DateTime.now().toUtc();
      for (var i = 0; i < 5; i++) {
        var q = new Query<TestModel>()
          ..values.createdAt = now
          ..values.name = "$i";
        allObjects.add(await q.insert());

        now = now.add(new Duration(seconds: 1));
      }
    });

    tearDownAll(() async {
      await app.channel.context.persistentStore.close();
      await app.stop();
    });

    test("Can get one object", () async {
      var resp = await client.request("/controller/1").get();
      expect(resp, hasResponse(200, allObjects.first.asMap()));
    });

    test("Can get all objects", () async {
      var resp = await client.request("/controller").get();
      expect(resp, hasResponse(200, allObjects.map((m) => m.asMap()).toList()));
    });

    test("Can update an object", () async {
      var expectedMap = {
        "id": 1,
        "name": "Fred",
        "createdAt": allObjects.first.createdAt.toIso8601String()
      };

      var resp = await (client.request("/controller/1")
            ..json = {"name": "Fred"})
          .put();
      expect(resp, hasResponse(200, expectedMap));

      expect(await client.request("/controller/1").get(),
          hasResponse(200, expectedMap));
      expect(await client.request("/controller/2").get(),
          hasResponse(200, allObjects[1].asMap()));
    });

    test("Can create an object", () async {
      var resp = await (client.request("/controller")
            ..json = {
              "name": "John",
              "createdAt": new DateTime(2000, 12, 12).toUtc().toIso8601String()
            })
          .post();

      var expectedMap = {
        "id": allObjects.length + 1,
        "name": "John",
        "createdAt": new DateTime(2000, 12, 12).toUtc().toIso8601String()
      };
      expect(resp, hasResponse(200, expectedMap));
      expect(await client.request("/controller/${expectedMap["id"]}").get(),
          hasResponse(200, expectedMap));
    });

    test("Can delete object", () async {
      expect(await client.request("/controller/1").delete(), hasStatus(200));
      expect(await client.request("/controller/1").get(), hasStatus(404));
    });
  });

  group("Standard operation failure cases", () {
    var app = new Application<TestChannel>();
    app.options.port = 8888;
    var client = new TestClient.onPort(8888);

    setUpAll(() async {
      await app.test();
    });

    tearDownAll(() async {
      await app.channel.context.persistentStore.close();
      await app.stop();
    });

    test("Get an object with the wrong type of path param returns 404",
        () async {
      expect(await client.request("/controller/one").get(), hasStatus(404));
    });

    test("Put an object with the wrong type of path param returns 404",
        () async {
      var resp = await (client.request("/controller/one")
            ..json = {"name": "Fred"})
          .put();
      expect(resp, hasStatus(404));
    });

    test("Delete an object with the wrong type of path param returns 404",
        () async {
      expect(await client.request("/controller/one").delete(), hasStatus(404));
    });
  });

  group("Objects that don't exist", () {
    var app = new Application<TestChannel>();
    app.options.port = 8888;
    var client = new TestClient.onPort(8888);

    setUpAll(() async {
      await app.test();
    });

    tearDownAll(() async {
      await app.channel.context.persistentStore.close();
      await app.stop();
    });

    test("Can't get object that doesn't exist - 404", () async {
      expect(await client.request("/controller/1").get(), hasStatus(404));
    });

    test("Can get all objects - there are none", () async {
      expect(await client.request("/controller").get(), hasResponse(200, []));
    });

    test("Updating an object returns 404", () async {
      expect(
          await (client.request("/controller/1")..json = {"name": "Fred"})
              .put(),
          hasStatus(404));
    });

    test("Delete nonexistant object is 404", () async {
      expect(
          await client.request("/controller/1").delete(),
          hasStatus(404));
    });
  });

  group("Extended GET requests", () {
    var app = new Application<TestChannel>();
    app.options.port = 8888;
    var client = new TestClient.onPort(8888);
    List<TestModel> allObjects = [];

    setUpAll(() async {
      await app.test();

      var now = new DateTime.now().toUtc();
      for (var i = 0; i < 10; i++) {
        var q = new Query<TestModel>()
          ..values.createdAt = now
          ..values.name = "${9 - i}";
        allObjects.add(await q.insert());

        now = now.add(new Duration(seconds: 1));
      }
    });

    tearDownAll(() async {
      await app.channel.context.persistentStore.close();
      await app.stop();
    });

    test("Can get all objects w/ count and offset", () async {
      expect(
          await client.request("/controller?count=2&offset=1").get(),
          hasResponse(
              200, allObjects.sublist(1, 3).map((m) => m.asMap()).toList()));
    });

    test("Can get all objects w/ sort descriptor", () async {
      expect(await client.request("/controller?sortBy=name,asc").get(),
          hasResponse(200, allObjects.reversed.map((m) => m.asMap()).toList()));
      expect(await client.request("/controller?sortBy=createdAt,asc").get(),
          hasResponse(200, allObjects.map((m) => m.asMap()).toList()));
    });

    test(
        "Getting all objects with sort descriptor referencing unknown key fails",
        () async {
      expect(
          await client.request("/controller?sortBy=foobar,asc").get(),
          hasResponse(400,
              {"error": "cannot sort by '[foobar,asc]'"}));
    });

    test("Getting all objects with a unknown sort descriptor order fails",
        () async {
      expect(
          await client.request("/controller?sortBy=name,name").get(),
          hasResponse(400,
              {"error": "invalid 'sortBy' format. syntax: 'name,asc' or 'name,desc'."}));
    });

    test("Getting all objects with bad syntax fails", () async {
      var resp = await client.request("/controller?sortBy=name,asc,bar").get();
      expect(resp, hasResponse(400,
              {"error": "invalid 'sortyBy' format. syntax: 'name,asc' or 'name,desc'."}));
    });

    test("Paging after", () async {
      expect(
          await client
              .request(
                  "/controller?pageBy=createdAt&pageAfter=${allObjects[5].createdAt.toIso8601String()}")
              .get(),
          hasResponse(
              200, allObjects.sublist(6).map((m) => m.asMap()).toList()));
    });

    test("Paging before", () async {
      expect(
          await client
              .request(
                  "/controller?pageBy=createdAt&pagePrior=${allObjects[5].createdAt.toIso8601String()}")
              .get(),
          hasResponse(
              200,
              allObjects
                  .sublist(0, 5)
                  .reversed
                  .map((m) => m.asMap())
                  .toList()));
    });

    test("Paging with null value", () async {
      expect(
          await client
              .request("controller?pageBy=createdAt&pageAfter=null")
              .get(),
          hasResponse(200, allObjects.map((m) => m.asMap()).toList()));
    });

    test("Paging with no pageAfter/pagePrior", () async {
      expect(
          await client.request("controller?pageBy=createdAt").get(),
          hasResponse(400, {
            "error":
                "missing required parameter 'pageAfter' or 'pagePrior' when 'pageBy' is given"
          }));
    });

    test("Paging with wrong key", () async {
      expect(
          await client.request("/controller?pageBy=foobar&pagePrior=10").get(),
          hasResponse(400,
              {"error": "cannot page by 'foobar'"}));
    });
  });

  group("Documentation", () {
    Map<String, APIOperation> collectionOperations;
    Map<String, APIOperation> idOperations;
    setUpAll(() async {
      final context = new APIDocumentContext(new APIDocument()
        ..info = new APIInfo("x", "1.0.0")
        ..paths = {}
        ..components = new APIComponents());

      var dataModel = new ManagedDataModel([TestModel]);
      ManagedContext.defaultContext =
      new ManagedContext(dataModel, new DefaultPersistentStore());
      final c = new ManagedObjectController<TestModel>();
      c.prepare();

      collectionOperations = c.documentOperations(context, "/", new APIPath());
      idOperations = c.documentOperations(context, "/", new APIPath(parameters: [new APIParameter.path("id")]));

      ManagedContext.defaultContext.documentComponents(context);

      await context.finalize();
    });

    test("getObject", () {
      var op = idOperations["get"];
      expect(op.id, "getTestModel");

      expect(op.responses.length, 2);

      expect(op.responses["404"], isNotNull);
      expect(op.responses["200"].content["application/json"].schema.referenceURI, "#/components/schemas/TestModel");
    });

    test("createObject", () {
      var op = collectionOperations["post"];
      expect(op.id, "createTestModel");

      expect(op.responses.length, 4);

      expect(op.responses["409"], isNotNull);
      expect(op.responses["422"], isNotNull);
      expect(op.responses["400"], isNotNull);
      expect(op.responses["200"].content["application/json"].schema.referenceURI, "#/components/schemas/TestModel");
      expect(op.requestBody.content["application/json"].schema.referenceURI, "#/components/schemas/TestModel");
    });

    test("updateObject", () {
      var op = idOperations["put"];
      expect(op.id, "updateTestModel");

      expect(op.responses.length, 5);

      expect(op.responses["404"], isNotNull);
      expect(op.responses["409"], isNotNull);
      expect(op.responses["422"], isNotNull);
      expect(op.responses["400"], isNotNull);
      expect(op.responses["200"].content["application/json"].schema.referenceURI, "#/components/schemas/TestModel");
      expect(op.requestBody.content["application/json"].schema.referenceURI, "#/components/schemas/TestModel");
    });

    test("deleteObject", () {
      var op = idOperations["delete"];
      expect(op.id, "deleteTestModel");

      expect(op.responses.length, 2);

      expect(op.responses["404"], isNotNull);
      expect(op.responses["200"].content, isNull);
    });

    test("getObjects", () {
      var op = collectionOperations["get"];
      expect(op.id, "getTestModels");

      expect(op.responses.length, 2);
      expect(op.parameters.length, 6);
      expect(op.parameters.every((p) => p.isRequired == false), true);

      expect(op.responses["400"], isNotNull);
      expect(op.responses["200"].content["application/json"].schema.type, APIType.array);
      expect(op.responses["200"].content["application/json"].schema.items.referenceURI, "#/components/schemas/TestModel");
    });
  });

  group("With dynamic entity", () {
    var app = new Application<TestChannel>();
    app.options.port = 8888;
    var client = new TestClient.onPort(8888);
    List<TestModel> allObjects = [];

    setUpAll(() async {
      await app.test();

      var now = new DateTime.now().toUtc();
      for (var i = 0; i < 10; i++) {
        var q = new Query<TestModel>()
          ..values.createdAt = now
          ..values.name = "${9 - i}";
        allObjects.add(await q.insert());

        now = now.add(new Duration(seconds: 1));
      }
    });

    tearDownAll(() async {
      await app.channel.context.persistentStore.close();
      await app.stop();
    });


    test("Can get one object", () async {
      var resp = await client.request("/dynamic/1").get();
      expect(resp, hasResponse(200, allObjects.first.asMap()));
    });

    test("Can get all objects", () async {
      var resp = await client.request("/dynamic").get();
      expect(resp, hasResponse(200, allObjects.map((m) => m.asMap()).toList()));
    });

  });
}

class TestChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    var dataModel = new ManagedDataModel([TestModel]);
    var persistentStore = new PostgreSQLPersistentStore(
        "dart", "dart", "localhost", 5432, "dart_test");
    context = new ManagedContext(dataModel, persistentStore);
    ManagedContext.defaultContext = context;

    var targetSchema = new Schema.fromDataModel(context.dataModel);
    var schemaBuilder = new SchemaBuilder.toSchema(
        context.persistentStore, targetSchema,
        isTemporary: true);

    var commands = schemaBuilder.commands;
    for (var cmd in commands) {
      await context.persistentStore.execute(cmd);
    }
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router
        .route("/controller/[:id]")
        .link(() => new ManagedObjectController<TestModel>());

    router
      .route("/dynamic/[:id]")
      .link(() => new ManagedObjectController.forEntity(context.dataModel.entityForType(TestModel)));
    return router;
  }
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int id;

  String name;
  DateTime createdAt;
}