![banner-01](https://user-images.githubusercontent.com/1287098/68531964-ccead400-0320-11ea-93a6-fa83b9183dd8.png)


a flutter library to make HTTP requests (inspired by python [requests](https://github.com/psf/requests) module). It comes with JSON support and a lightweight implementation to store cookies like a browser.

### Cookies, huh?
Server side cookies (via response header `SET-COOKIE`) are stored using the assistance of `shared_preferences`. Stored cookies will be send seamlessly on the next http requests you make to the same domain (simple implementation, similar to a web browser)

## About this fork
I created this fork for a project of mine as I came across two major problems of the original code:
  1. Cookies sent together with a redirect HTTP response (e.g. 303) were ignored
  2. Cookies using flags instead of keyword arguments ('HttpOnly' instead of 'HttpOnly=true' were not correctly parsed)

Both problems are fixed in this fork.

This fork provides a few more options ('followRedirect', 'maxRedirects' and 'client' for a custom HttpClient) and has a slightly changed API usage (see below) to clean up library code.

## Install

Add this to your package's pubspec.yaml file:

```yaml
dependencies:
  requests: ^3.0.3
```

## Usage
Start by importing the library
```dart
import 'package:requests/requests.dart';
```

Let's make a simple HTTP request

```dart
var r = await Requests.get("https://google.com");
r.raiseForStatus();
String body = r.content();
```


### the `Response` object
just like in python's request module, the `Response` object has this functionallity

- `r.throwForStatus()` - will throw an exception if the response `statusCode` is not a great success.
- `r.raiseForStatus()` - same as `throwForStatus`
- `r.statusCode` - the response status code
- `r.url` - the url in the request 
- `r.success` - a boolean. `true` indicates that the request was a great success 
- `r.hasError` - a boolean. `true` indicates that the request was not a great success 
- `r.bytes()` - return the body in the respone as a list of bytes 
- `r.content()` - return the body in the respone as a string
- `r.json()` - recodes the body in the respone and returns the result (dynamic type)


### Optional Arguments

- `json` - a `dynamic` object that will be json encoded and then be set as the request's body
- `body` - a raw string to be used as the request's body
- `bodyEncoding` - default `RequestBodyEncoding.FormURLEncoded`. will set the `content-type` header
- `headers` - `Map<String, String>` of custom client headers to add in the request
- `options` - an instance of RequestOptions (shorthand: `O`)

> 💡 Only one optional argument can be used in a single request `body` or `json`
 
 
 ### Class Methods

- `.getHostname(url)` - returns the hostname of the given url
- `.clearStoredCookies(hostname)` - clears the stored cookies for the hostname
- `.setStoredCookies(hostname, Map<String, String>)` - set the stored cookies for the hostname
- `.getStoredCookies(hostname)` - returns a Map<String, String> of the stored cookies for the hostname

 
## Examples
 
HTTP post, body encoded as application/x-www-form-urlencoded, parse response as json

```dart
var r = await Requests.post(
  "https://reqres.in/api/users",
  body: {
    "userId": 10,
    "id": 91,
    "title": "aut amet sed",
  },
  bodyEncoding: RequestBodyEncoding.FormURLEncoded);

r.raiseForStatus();
dynamic json = r.json();
print(json['id']);
```

---

HTTP GET with some options:

```dart
var r = await Requests.get(
  "https://example.com",
  options: O(
    followRedirect: false,  // do not follow redirect responses (301, 302, 303, ...)
    verifySSL: false,       // ignore invalid SSL certificates (renamed from the original `verify`)
    persistCookies: false,  // do not keep cookies
    timeoutSeconds: 20      // timeout, obviously
  ));
  r.raiseForStatus();
```

---

HTTP delete

```dart
var r = await Requests.delete("https://reqres.in/api/users/10");
r.raiseForStatus();
```

---

Ignore SSL self-signed certificate

```dart
var r = await Requests.get('https://expired.badssl.com/', verify: false);
r.raiseForStatus();
``` 

---

Play with stored cookies

```dart
String url = "https://reqres.in/api/users/10";
String hostname = Requests.getHostname(url);
await Requests.clearStoredCookies(hostname);
await Requests.setStoredCookies(hostname, {'session': 'bla'});
var cookies = await Requests.getStoredCookies(hostname);
expect(cookies.keys.length, 1);
await Requests.clearStoredCookies(hostname);
cookies = await Requests.getStoredCookies(hostname);
expect(cookies.keys.length, 0);
``` 

<a href="https://www.freepik.com/free-photos-vectors/business">Business vector created by freepik - www.freepik.com</a>
