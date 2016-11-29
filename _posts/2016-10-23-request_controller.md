---
layout: page
title: "Handling Requests"
category: http
date: 2016-06-19 21:22:35
order: 3
---

An Aqueduct application's job is to respond to HTTP requests. Each request in an Aqueduct application is an instance of `Request` (see [Request and Response Objects](request_and_response.html)). The behavior of processing and responding to requests is carried out by instances of `RequestController`.

There are many subclasses of `RequestController` that perform different processing steps on a request. Some request controllers - like `HTTPController` - implement the business logic of handling a request. Others, like `Authorizer`, validate authentication data in a request. `RequestController`s are chained together to form a processing pipeline that requests go through. `RequestController` is often subclassed to create reusable components for those pipelines.

## Request Streams and RequestController Listeners

Aqueduct applications use a reactive programming model to respond to HTTP requests. A reactive model mirrors a real life assembly line. In an assembly line of cars, the body of a car gets put on a conveyor belt. The first worker puts on a steering wheel, the next puts on tires and the last one paints the car a color. The car is then removed from the conveyor belt and sold. Each worker has a specific job in a specific order - they rely on the rest of the assembly line to complete the car, but their job is isolated. If a worker notices a defect in their area of expertise, they remove the car from the assembly line before it is finished and discard it.

A reactive application works the same way. An *event* is added to a *stream*, just like the body of the car gets put on a conveyor belt. A series of *event listeners* process the event by taking a specific operation in isolation. If an event listener rejects the event, the event is discarded and no more listeners receive it. Information can be added to the event as it passes through listeners. When the last listener finishes its job, the event is completed.

In Aqueduct, every HTTP request is an event and an instance of `Request`. Event listeners are instances of `RequestController`. When a request controller gets a request, it can choose to respond to it. This sends the HTTP response back to the client. Every `RequestController` may have a `nextController` property - a reference to another `RequestController`. A `RequestController` can choose *not* to respond to a request and pass the request to its `nextController`.

Controllers that pass a request on are commonly referred to as *middleware*. An example of middleware is an `Authorizer` - a `RequestController` subclass that validates the authentication credentials of a request. An `Authorizer` will only allow a request to go to its `nextController` if the credentials are valid. Otherwise, it responds to the request with an authentication error - its `nextController` will never see it. Some `RequestController`s, like `Router`, have more than one `nextController`, allowing the stream of requests to be split based on some condition (see [Routing](routing.html) for more information).

An Aqueduct application, then, is a hierarchy of `RequestController`s that a request travels through to get responded to. In every Aqueduct application, there is a root `RequestController` that is first to receive every request. The specifics of that root controller are covered in [The Application Object](request_sink.html); for now, we'll focus on the fundamentals of how `RequestController`s work together to form a series of steps to process a request.

Based on the previous description, you might envision a series of `RequestController`s being set up like so:

```dart
var c1 = new RequestController();
var c2 = new RequestController();
var c3 = new RequestController();

c1.nextController = c2;
c2.nextController = c3;
```

However, this is rather cumbersome code. Instead, the code to organize controllers is similar to how higher ordered `List<T>` methods or `Stream<T>` methods are structured. For example, the following code takes a `List<String>`, maps it to a `List<int>` and then sums them together:

```dart
["1", "2", "3"]
  .map((s) => int.parse(s))
  .fold(0, (sum, next) => sum + next);
```

This code works because `List<T>` has methods like `map` which (effectively) return another `List<T>` by performing an operation on each element in the list. `RequestController`s work in the same way - there are three methods, `pipe`, `listen` and `generate` that all controllers have. Each of these methods sets the `nextController` of the receiver and returns that `nextController` so another one can be attached. A `Request` goes through those controllers in order.

```dart
var root = new RequestController();
root
  .listen((Request req) async => req)
  .pipe(new Authorizer())
  .generate(() => new ManagedObjectController<Account>());
```

When a request is received by `root`, it flows through the next three `RequestController`s set up by `listen`, `pipe` and `generate`. Along the way, if any of those controllers respond to the request, the request is not delivered to the next controller in line.

Each of these three methods set the `nextController` property of the receiver, but have a distinct usage.

`listen` is the most primitive of the three: it takes a closure that takes a `Request` and returns either a `Future<Request>` or `Future<Response>`. If that closure returns a `Future<Response>`, the request is responded to and the `Authorizer` and `ManagedObjectController<Account>` never receive the request. Otherwise, it moves on to the `Authorizer`.

While using a closure is a succinct way to describe a request processing step, you will often want to reuse the behavior of a controller across streams. Behind the scenes, the `listen` closure is wrapped in an instance of `RequestController`. In the example code, `pipe` is invoked on that controller. This method takes an instance of a `RequestController` subclass and inserts it into a series of event listeners. Therefore, when appending event listeners, `pipe` is for objects and `listen` is for closures.

The `generate` method behaves similarly to `pipe`, except that for each new request, a brand new instance of some controller is created. Thus, the argument to `generate` is a closure that creates a `RequestController` subclass instance.

This generating behavior is useful for `RequestController` subclasses like `HTTPController`, which have properties that reference the `Request` it is processing. Since Aqueduct applications process `Request`s asynchronously and can service more than one `Request` at a time, a controller that has properties that change for every `Request` would run into a problem; while they are waiting for an asynchronous operation to complete, a new `Request` could come in and change their properties. When the asynchronous operation completes, the reference to the previous request is lost. This would be bad.

`RequestController` subclasses that have properties that change for every request must be added as a listener using `generate`. To provide safety, these subclasses have `@cannotBeReused` metadata. If you try to `pipe` to a controller with this metadata, you'll get an exception at startup and a helpful error message telling you to use `generate`.

## Subclassing RequestController

By default, a `RequestController` does nothing with a `Request` but forward it on to its `nextController`. To provide specific handling code, you must create a subclass and override `processRequest`.

```dart
class Controller extends RequestController {
  @override
  Future<RequestControllerEvent> processRequest(Request request) async {
      ... return either request or a new Response ...
  }
}
```

`RequestControllerEvent` is either a `Request` or a `Response`. Therefore, this method returns either a `Future<Request>` or `Future<Response>` - just like the closure passed to `listen`. In fact, a `RequestController` created by `listen` implements `processRequest` to simply invoke the provided closure.

The return value of `processRequest` dictates the control flow of a request stream - if it returns a request, the request is passed on to the `nextController`. The `nextController` will then invoke its `processRequest` and this continues until a controller returns a response. If no controller responds to a request, no response will be sent to the client. You should avoid this behavior.

A controller must return the same instance of `Request` it receives, but it may attach additional information by adding key-value pairs to the request's `attachments`.

An `HTTPController` - a commonly used subclass of `RequestController` - overrides `processRequest` to delegate processing to another method depending on the HTTP method of the request. Subclasses of `RequestController` like `Authorizer` override `processRequest` to validate a request before it lets its `nextController` receive it. The pseudo-code of an `Authorizer` looks like this:

```dart
Future<RequestControllerEvent> processRequest(Request request) async {
    if (!isAuthorized(request)) {
      return new Response.unauthorized();
    }

    request.attachments["authInfo"] = authInfoFromRequest(request);
    return request;
}
```

In other words, the `processRequest` method is where controller-specific logic goes. However, you never call this method directly; it is a callback for when a request controller decides it is time to process a request. A `RequestController` receives requests through its `receive` method. This entry point sets up a try-catch block and invokes `processRequest`, gathering its result to determine the next course of action - whether to pass it on to the next controller or respond. You do not call `receive` directly, `RequestController`s already know how to use this method to send requests to their `nextController`.

When a `RequestController` responds to a request, it does not invoke `receive` on its `nextController`; this is what "ends" the event from traveling further in the stream. A `RequestController` also logs some of the details of the request and the response it sent.

Exceptions thrown in `processRequest` bubble up to the try-catch block established in `receive`. Therefore, you typically don't have to do any explicit exception handling code in your request processing code. The benefit here is cleaner code, but also if you fail to catch an exception, the request will still get responded to. When an exception is thrown from within `processRequest`, your request processing code is terminated, an appropriate response is sent and no subsequent controllers are sent the request. (The details of how an exception dictates a response are in a later section.) If you don't want a particular exception to use this behavior, you can catch it and take your own action.

Prior to invoking `processRequest`, the implementation of `receive` will determine if the request is a CORS request and take a different action. See a later section for details on handling CORS requests.

Classes like `Router`, which have more than one "next controller", override `receive` instead of `processRequest`. In general, you want to avoid overriding `receive`, because its behavior is integral to the behavior of an Aqueduct application as a whole.

## Exception Handling

If an exception is thrown while processing a request, it will be caught by the `RequestController` doing the processing. The controller will respond to the HTTP request with an appropriate status code and no subsequent controllers will receive the request.

There are two types of exceptions that a `RequestController` will interpret to return a meaningful status code: `HTTPResponseException` and `QueryException`. Any other uncaught exceptions will result in a 500 status code error.

`QueryException`s are generated by the Aqueduct ORM. A request controller interprets these types of exceptions to return a suitable status code. The following reasons for the exception generate the following status codes:

|Reason|Status Code|
|---|---|
|A programmer error (bad query syntax)|500|
|Unique constraint violated|409|
|Invalid input|400|
|Database can't be reached|503|

An `HTTPResponseException` can be thrown at anytime to escape early from processing and return a response. Exceptions of these type allow you to specify the status code and a message. The message is encoded in a JSON object for the key "error". Some classes in Aqueduct will throw an exception of this kind if some precondition isn't met. For example, `AuthorizationBearerParser` throws this exception if there is no authorization header to parse.

You may add your own try-catch blocks to request processing code to either catch and reinterpret the behavior of `HTTPResponseException` and `QueryException`, or for any other reason.

Other than `HTTPResponseException`s, exceptions are always logged along with some details of the request that generated the exception. `HTTPResponseException`s are not logged, as they are used for control flow and are considered "normal" operation.

## CORS Support

All request controllers have built-in behavior for handling CORS requests from a browser. When a preflight request is received from a browser (an OPTIONS request with Access-Control-Request-Method header and Origin headers), any request controller receiving this request will immediately pass it on to its `nextController`. The final controller listening to the stream will use its policy to validate and return a response to the HTTP client.

Using the last controller in a stream allows endpoints to decide the validity of a CORS request. Thus, even if a request doesn't make its way through the stream - perhaps because it failed to be authorized - the response will have the appropriate headers to indicate to the browser the acceptable operations for that endpoint.

CORS headers are applied by a `RequestController` after it invokes `processRequest`, but before it responds to the request. These headers are dictated by the policy of the last controller listening to the stream.

Every `RequestController` has a default policy. This policy can be changed on a per-controller basis by modifying it in the controller's constructor.

The default policy may also be changed at the global level by modifying `CORSPolicy.defaultPolicy`. The default policy is permissive: POST, PUT, DELETE and GET are allowed methods. All origins are valid (\*). Authorization, X-Requested-With and X-Forwarded-For are allowed request headers, along with the list of simple headers: Cache-Control, Content-Language, Content-Type, Expires, Last-Modified, Pragma, Accept, Accept-Language and Origin.