# 3. Storing Data in a Database

## Inserting Data

Now that we can persist data between runs of our application, we can add operations for creating new heroes, updating existing heroes and deleting heroes. Let's start by creating an operation to "create a new hero". This operation will be `POST /heroes`. The client making this request will need to provide a JSON representation of a hero in the request body.

In `heroes_controller.dart`, add the following operation method:

```dart
@Operation.post()
Future<Response> createHero(@Bind.body() Hero hero) async {
  final query = new Query<Hero>()
    ..values.name = hero.name;

  final insertedHero = await query.insert();

  return new Response.ok(insertedHero);
}
```

There's a bit going on here, so let's deconstruct it. First, we know this operation method is bound to `POST /heroes` because:

1. The `@Operation.post()` annotation indicates this method responds to `POST`.
2. We've routed `/heroes` and `/heroes/:id` to this controller, but this operation method does not bind any path variables, so the only valid path is `/heroes`.

We have bound the *body* of the HTTP request with this argument:

```dart
@Bind.body() Hero hero
```

Before Aqueduct calls our `createHero(hero)` method, it will read the JSON body of the `POST /heroes` request into a `Map<String, dynamic>`. Then, Aqueduct will create a new instance of `Hero` and invoke its `readFromMap(map)` method that it inherits from `ManagedObject<T>`. The body of this operation should then look like this:

```json
{
  "name": "My Hero"
}
```

(You wouldn't need to provide an `id` in the body since it is autogenerated by the database.)

!!! note "Other Content-Types"
    Aqueduct can decode JSON and form data by default. For other content types, see the [API reference for HTTPCodecRepository](https://www.dartdocs.org/documentation/aqueduct/latest/aqueduct/HTTPCodecRepository-class.html).

An insert query creates a row in the database. The values for each column are provided through the `Query.values` property. Like `Query.where`, `Query.values` is also an instance of a `Hero` and therefore has an `id` and `name` property.

Re-run your `heroes` application. On [http://aqueduct-tutorial.stablekernel.io](http://aqueduct-tutorial.stablekernel.io), click on the `Heroes` button on the top of the screen. In the text field, enter a new hero name and click `Add`. You'll see your new hero added to the list! You can shutdown your application and run it again and you'll still be able to fetch your new hero.

![Aqueduct Tutorial Third Run](../img/run3.png)

!!! tip "Query Construction"
    Properties like `values` and `where` prevent errors by type and name checking columns with the analyzer. They're also great for speeding up writing code because your IDE will autocomplete property names. There is [specific behavior](../db/advanced_queries.md) a query uses to decide whether it should include a value from these two properties in the SQL it generates.