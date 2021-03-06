import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ManagedContext context;
  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Fetching an object gets entire object", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel(name: "Joe", email: "a@a.com");
    var req = new Query<TestModel>()..values = m;
    var item = await req.insert();

    req = new Query<TestModel>()
      ..predicate = new QueryPredicate("id = @id", {"id": item.id});
    item = await req.fetchOne();

    expect(item.name, "Joe");
    expect(item.email, "a@a.com");

    var dynQuery = new Query.forEntity(context.dataModel.entityForType(TestModel))
      ..where["id"] = whereEqualTo(item.id);
    item = await dynQuery.fetchOne();
    expect(item.name, "Joe");
    expect(item.email, "a@a.com");
  });

  test("Query with dynamic entity and mis-matched context throws exception", () async {
    context = await contextWithModels([TestModel]);

    var someOtherContext = new ManagedContext.standalone(new ManagedDataModel([]), null);
    try {
      new Query.forEntity(context.dataModel.entityForType(TestModel), someOtherContext);
      expect(true, false);
    } on QueryException catch (e) {
      expect(e.toString(), contains("Cannot instantiate"));
    }
  });

  test("Specifying resultProperties works", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel(name: "Joe", email: "b@a.com");
    var req = new Query<TestModel>()..values = m;

    var item = await req.insert();
    var id = item.id;

    req = new Query<TestModel>()
      ..predicate = new QueryPredicate("id = @id", {"id": item.id})
      ..returningProperties((t) => [t.id, t.name]);

    item = await req.fetchOne();

    expect(item.name, "Joe");
    expect(item.id, id);
    expect(item.email, isNull);
  });

  test("Ascending sort descriptors work", () async {
    context = await contextWithModels([TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel(name: "Joe$i", email: "asc$i@a.com");
      var req = new Query<TestModel>()..values = m;
      await req.insert();
    }

    var req = new Query<TestModel>()
      ..sortBy((t) => t.email, QuerySortOrder.ascending)
      ..predicate = new QueryPredicate("email like @key", {"key": "asc%"});

    var result = await req.fetch();

    for (int i = 0; i < 10; i++) {
      expect(result[i].email, "asc$i@a.com");
    }

    req = new Query<TestModel>()..sortBy((t) => t.id, QuerySortOrder.ascending);
    result = await req.fetch();

    int idIndex = 0;
    for (TestModel m in result) {
      int next = m.id;
      expect(next, greaterThan(idIndex));
      idIndex = next;
    }
  });

  test("Descending sort descriptors work", () async {
    context = await contextWithModels([TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel(name: "Joe$i", email: "desc$i@a.com");

      var req = new Query<TestModel>()..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>()
      ..sortBy((t) => t.email, QuerySortOrder.descending)
      ..predicate = new QueryPredicate("email like @key", {"key": "desc%"});
    var result = await req.fetch();

    for (int i = 0; i < 10; i++) {
      int v = 9 - i;
      expect(result[i].email, "desc$v@a.com");
    }
  });

  test("Cannot sort by property that doesn't exist", () async {
    context = await contextWithModels([TestModel]);
    try {
      new Query<TestModel>()
        ..sortBy((u) => u["nonexisting"], QuerySortOrder.ascending);
      expect(true, false);
    } on QueryException catch (e) {
      expect(e.toString(), contains("property does not exist"));
    }
  });

  test("Cannot sort by relationship property", () async {
    context = await contextWithModels([GenUser, GenPost]);
    try {
      new Query<GenUser>()
          ..sortBy((u) => u.posts, QuerySortOrder.ascending);
      expect(true, false);
    } on QueryException catch (e) {
      expect(e.toString(), contains("results cannot be sorted by relationship properties"));
    }
  });

  test("Order by multiple sort descriptors work", () async {
    context = await contextWithModels([TestModel]);

    for (int i = 0; i < 10; i++) {
      var m = new TestModel(name: "Joe${i%2}", email: "multi$i@a.com");

      var req = new Query<TestModel>()..values = m;

      await req.insert();
    }

    var req = new Query<TestModel>()
      ..sortBy((t) => t.name, QuerySortOrder.ascending)
      ..sortBy((t) => t.email, QuerySortOrder.descending)
      ..predicate = new QueryPredicate("email like @key", {"key": "multi%"});

    var result = await req.fetch();

    expect(result[0].name, "Joe0");
    expect(result[0].email, "multi8@a.com");

    expect(result[1].name, "Joe0");
    expect(result[1].email, "multi6@a.com");

    expect(result[2].name, "Joe0");
    expect(result[2].email, "multi4@a.com");

    expect(result[3].name, "Joe0");
    expect(result[3].email, "multi2@a.com");

    expect(result[4].name, "Joe0");
    expect(result[4].email, "multi0@a.com");

    expect(result[5].name, "Joe1");
    expect(result[5].email, "multi9@a.com");

    expect(result[6].name, "Joe1");
    expect(result[6].email, "multi7@a.com");

    expect(result[7].name, "Joe1");
    expect(result[7].email, "multi5@a.com");

    expect(result[8].name, "Joe1");
    expect(result[8].email, "multi3@a.com");

    expect(result[9].name, "Joe1");
    expect(result[9].email, "multi1@a.com");
  });

  test("Fetching an invalid key fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel(name: "invkey", email: "invkey@a.com");

    var req = new Query<TestModel>()..values = m;
    await req.insert();

    req = new Query<TestModel>()
      ..returningProperties((t) => [t.id, t["badkey"]]);

    var successful = false;
    try {
      await req.fetch();
      successful = true;
    } on QueryException catch (e) {
      expect(e.toString(), "Property badkey does not exist on simple");
      expect(e.event, QueryExceptionEvent.internalFailure);
    }
    expect(successful, false);
  });

  test("Value for foreign key in predicate", () async {
    context = await contextWithModels([GenUser, GenPost]);

    var u1 = new GenUser()..name = "Joe";
    var u2 = new GenUser()..name = "Fred";
    u1 = await (new Query<GenUser>()..values = u1).insert();
    u2 = await (new Query<GenUser>()..values = u2).insert();

    for (int i = 0; i < 5; i++) {
      var p1 = new GenPost()..text = "${2 * i}";
      p1.owner = u1;
      await (new Query<GenPost>()..values = p1).insert();

      var p2 = new GenPost()..text = "${2 * i + 1}";
      p2.owner = u2;
      await (new Query<GenPost>()..values = p2).insert();
    }

    var req = new Query<GenPost>()
      ..predicate = new QueryPredicate("owner_id = @id", {"id": u1.id});
    var res = await req.fetch();
    expect(res.length, 5);
    expect(
        res
            .map((p) => p.text)
            .where((text) => num.parse(text) % 2 == 0)
            .toList()
            .length,
        5);

    var query = new Query<GenPost>();
    query.where["owner"] = whereRelatedByValue(u1.id);
    res = await query.fetch();

    GenUser user = res.first.owner;
    expect(user, isNotNull);
    expect(res.length, 5);
    expect(
        res
            .map((p) => p.text)
            .where((text) => num.parse(text) % 2 == 0)
            .toList()
            .length,
        5);
  });

  test("Fetch object with null reference", () async {
    context = await contextWithModels([GenUser, GenPost]);
    var p1 = await (new Query<GenPost>()..values = (new GenPost()..text = "1"))
        .insert();

    var req = new Query<GenPost>();
    p1 = await req.fetchOne();

    expect(p1.owner, isNull);
  });

  test("Omits specific keys", () async {
    context = await contextWithModels([Omit]);

    var iq = new Query<Omit>()..values = (new Omit()..text = "foobar");

    var result = await iq.insert();
    expect(result.id, greaterThan(0));
    expect(result.backingMap["text"], isNull);

    var fq = new Query<Omit>()
      ..predicate = new QueryPredicate("id=@id", {"id": result.id});

    var fResult = await fq.fetchOne();
    expect(fResult.id, result.id);
    expect(fResult.backingMap["text"], isNull);
  });

  test(
      "Throw exception when fetchOne returns more than one because the fetchLimit can't be applied to joins",
      () async {
    context = await contextWithModels([GenUser, GenPost]);

    var objects = [new GenUser()..name = "Joe", new GenUser()..name = "Bob"];

    for (var o in objects) {
      var req = new Query<GenUser>()..values = o;
      await req.insert();
    }

    try {
      var q = new Query<GenUser>()..join(set: (u) => u.posts);
      await q.fetchOne();

      expect(true, false);
    } on QueryException catch (e) {
      expect(
          e.toString(),
          contains(
              "Query expected to fetch one instance, but 2 instances were returned."));
    }
  });

  test(
      "Including RelationshipInverse property can only be done by using name of property",
      () async {
    context = await contextWithModels([GenUser, GenPost]);

    var u1 = await (new Query<GenUser>()..values.name = "Joe").insert();

    await (new Query<GenPost>()
          ..values.text = "text"
          ..values.owner = u1)
        .insert();

    var q = new Query<GenPost>()..returningProperties((p) => [p.id, p.owner]);

    var result = await q.fetchOne();
    expect(result.owner.id, 1);
    expect(result.owner.backingMap.length, 1);

    q = new Query<GenPost>()..returningProperties((p) => [p.id, p["owner_id"]]);
    try {
      await q.fetchOne();
      expect(true, false);
    } on QueryException catch (e) {
      expect(e.toString(),
          contains("Property owner_id does not exist on _GenPost"));
    }
  });

  test("Can use public accessor to private property in where", () async {
    context = await contextWithModels([PrivateField]);

    await (new Query<PrivateField>()).insert();
    var q = new Query<PrivateField>()
      ..where.public = "x";
    var result = await q.fetchOne();
    expect(result.public, "x");

    q = new Query<PrivateField>()
      ..where.public = "y";
    result = await q.fetchOne();
    expect(result, isNull);
  });

  test("When fetching valid enum value from db, is available as enum value and in where", () async {
    context = await contextWithModels([EnumObject]);

    var q = new Query<EnumObject>()
      ..values.enumValues = EnumValues.abcd;

    await q.insert();

    q = new Query<EnumObject>();
    var result = await q.fetchOne();
    expect(result.enumValues, EnumValues.abcd);
    expect(result.asMap()["enumValues"], "abcd");

    q = new Query<EnumObject>()
      ..where.enumValues = EnumValues.abcd;
    result = await q.fetchOne();
    expect(result, isNotNull);

    q = new Query<EnumObject>()
      ..where.enumValues = EnumValues.efgh;
    result = await q.fetchOne();
    expect(result, isNull);
  });

  test("When fetching invalid enum value from db, throws exception", () async {
    context = await contextWithModels([EnumObject]);

    await context.persistentStore.execute("INSERT INTO _enumobject (enumValues) VALUES ('foobar')");

    try {
      var q = new Query<EnumObject>();
      await q.fetch();
      expect(true, false);
    } on QueryException catch (e) {
      expect(e.toString(), contains("'foobar'"));
      expect(e.toString(), contains("'EnumObject.enumValues'"));
    }
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {
  TestModel({String name: null, String email: null}) {
    this.name = name;
    this.email = email;
  }
}

class _TestModel {
  @managedPrimaryKey
  int id;

  String name;

  @ManagedColumnAttributes(nullable: true, unique: true)
  String email;

  static String tableName() {
    return "simple";
  }

  @override
  String toString() {
    return "TestModel: $id $name $email";
  }
}

class GenUser extends ManagedObject<_GenUser> implements _GenUser {}

class _GenUser {
  @managedPrimaryKey
  int id;

  String name;

  ManagedSet<GenPost> posts;

  static String tableName() {
    return "GenUser";
  }
}

class GenPost extends ManagedObject<_GenPost> implements _GenPost {}

class _GenPost {
  @managedPrimaryKey
  int id;

  String text;

  @ManagedRelationship(#posts,
      onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: false)
  GenUser owner;
}

class Omit extends ManagedObject<_Omit> implements _Omit {}

class _Omit {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(omitByDefault: true)
  String text;
}

class PrivateField extends ManagedObject<_PrivateField> implements _PrivateField {
  PrivateField() : super() {
    _private = "x";
  }

  set public(String p) {
    _private = p;
  }

  String get public => _private;
}
class _PrivateField {
  @managedPrimaryKey
  int id;

  String _private;
}

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}
class _EnumObject {
  @managedPrimaryKey
  int id;

  EnumValues enumValues;
}

enum EnumValues {
  abcd, efgh, other18
}