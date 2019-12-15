import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;
import 'package:logging/logging.dart';
import 'dart:convert';
import 'dart:core';
import 'common.dart';
import 'event.dart';
import 'dart:io';

enum RequestBodyEncoding { JSON, FormURLEncoded, PlainText }

final Logger log = Logger('requests');

class Response {
  final http.Response _rawResponse;

  Response(this._rawResponse);

  get statusCode => _rawResponse.statusCode;

  get hasError => (400 <= statusCode) && (statusCode < 600);

  get success => !hasError;

  get url => _rawResponse.request.url;

  throwForStatus() {
    if (!success) {
      throw HTTPException("Invalid HTTP status code $statusCode for url ${url}", this);
    }
  }

  raiseForStatus() {
    throwForStatus();
  }

  List<int> bytes() {
    return _rawResponse.bodyBytes;
  }

  String content() {
    return utf8.decode(bytes(), allowMalformed: true);
  }

  dynamic json() {
    return Common.fromJson(content());
  }
}

class HTTPException implements Exception {
  final String message;
  final Response response;

  HTTPException(this.message, this.response);
}

class Requests {

  const Requests();

  static final Event onError = Event();
  static const String HTTP_METHOD_GET = "get";
  static const String HTTP_METHOD_PUT = "put";
  static const String HTTP_METHOD_PATCH = "patch";
  static const String HTTP_METHOD_DELETE = "delete";
  static const String HTTP_METHOD_POST = "post";
  static const String HTTP_METHOD_HEAD = "head";
  static const RequestOptions DEFAULT_REQUEST_OPTIONS = RequestOptions();

  static const RequestBodyEncoding DEFAULT_BODY_ENCODING = RequestBodyEncoding.FormURLEncoded;

  static Set _cookiesKeysToIgnore = Set.from(["SameSite", "Path", "Domain", "Max-Age", "Expires", "Secure", "HttpOnly"]);

  static Map<String, String> _extractResponseCookies(responseHeaders) {
    Map<String, String> cookies = {};
    for (var key in responseHeaders.keys) {
      if (Common.equalsIgnoreCase(key, 'set-cookie')) {
        String cookie = responseHeaders[key];
        cookie.split(",").forEach((String one) {
          var c = one.split("=");
          if (c.length < 2) return;  // not a valid key-value pair
          if (c[0].contains(";")) return; // not a cookie name
          if (_cookiesKeysToIgnore.contains(c[0].trim())) return;  // ignored
          cookies[c[0]] = c[1].split(";")[0].trim();
        });
        break;
      }
    }

    return cookies;
  }

  static Future<Map> _constructRequestHeaders(String hostname, Map<String, String> customHeaders) async {
    var cookies = await getStoredCookies(hostname);
    String cookie = cookies.keys.map((key) => "$key=${cookies[key]}").join("; ");
    Map<String, String> requestHeaders = Map();
    requestHeaders['cookie'] = cookie;

    if (customHeaders != null) {
      requestHeaders.addAll(customHeaders);
    }
    return requestHeaders;
  }

  static Future<Map<String, String>> getStoredCookies(String hostname) async {
    try {
      String hostnameHash = Common.hashStringSHA256(hostname);
      String cookiesJson = await Common.storageGet('cookies-$hostnameHash');
      var cookies = Common.fromJson(cookiesJson);
      return Map<String, String>.from(cookies);
    } catch (e) {
      log.shout("problem reading stored cookies. fallback with empty cookies $e");
      return Map<String, String>();
    }
  }

  static Future setStoredCookies(String hostname, Map<String, String> cookies) async {
    String hostnameHash = Common.hashStringSHA256(hostname);
    String cookiesJson = Common.toJson(cookies);
    await Common.storageSet('cookies-$hostnameHash', cookiesJson);
  }

  static Future clearStoredCookies(String hostname) async {
    String hostnameHash = Common.hashStringSHA256(hostname);
    await Common.storageSet('cookies-$hostnameHash', null);
  }

  static String getHostname(String url) {
    var uri = Uri.parse(url);
    return "${uri.host}:${uri.port}";
  }

  static Future<Response> _handleHttpResponse(String hostname, http.StreamedResponse streamedResponse, bool persistCookies) async {
    if (persistCookies) {
      var responseCookies = _extractResponseCookies(streamedResponse.headers);
      if (responseCookies.isNotEmpty) {
        var storedCookies = await getStoredCookies(hostname);
        storedCookies.addAll(responseCookies);
        await setStoredCookies(hostname, storedCookies);
      }
    }

    var response = Response(await http.Response.fromStream(streamedResponse));

    if (response.hasError) {
      var errorEvent = {"response": response};
      onError.publish(errorEvent);
    }

    return response;
  }

  static Future<Response> head(String url, {headers, bodyEncoding = DEFAULT_BODY_ENCODING, http.Client client, options = DEFAULT_REQUEST_OPTIONS}) {
    return _httpRequest(HTTP_METHOD_HEAD, url, bodyEncoding: bodyEncoding, headers: headers, client: client, options: options);
  }

  static Future<Response> get(String url, {headers, bodyEncoding = DEFAULT_BODY_ENCODING, http.Client client, RequestOptions options = DEFAULT_REQUEST_OPTIONS}) {
    return _httpRequest(HTTP_METHOD_GET, url, bodyEncoding: bodyEncoding, headers: headers, client: client, options: options);
  }

  static Future<Response> patch(String url, {headers, bodyEncoding = DEFAULT_BODY_ENCODING, http.Client client, RequestOptions options = DEFAULT_REQUEST_OPTIONS}) {
    return _httpRequest(HTTP_METHOD_PATCH, url, bodyEncoding: bodyEncoding, headers: headers, client: client, options: options);
  }

  static Future<Response> delete(String url, {headers, bodyEncoding = DEFAULT_BODY_ENCODING, http.Client client, RequestOptions options = DEFAULT_REQUEST_OPTIONS}) {
    return _httpRequest(HTTP_METHOD_DELETE, url, bodyEncoding: bodyEncoding, headers: headers, client: client, options: options);
  }

  static Future<Response> post(String url, {json, body, bodyEncoding = DEFAULT_BODY_ENCODING, headers, http.Client client, RequestOptions options = DEFAULT_REQUEST_OPTIONS}) {
    return _httpRequest(HTTP_METHOD_POST, url, bodyEncoding: bodyEncoding, json: json, body: body, headers: headers, client: client, options: options);
  }

  static Future<Response> put(String url, {json, body, bodyEncoding = DEFAULT_BODY_ENCODING, headers, http.Client client, RequestOptions options = DEFAULT_REQUEST_OPTIONS}) {
    return _httpRequest(HTTP_METHOD_PUT, url, bodyEncoding: bodyEncoding, json: json, body: body, headers: headers, client: client, options: options);
  }

  static Future<Response> _httpRequest(String method, String url, {json, body, bodyEncoding = DEFAULT_BODY_ENCODING, headers, http.Client client, RequestOptions options = DEFAULT_REQUEST_OPTIONS}) async {
    client = _createHttpClient(client, options.verifySSL);

    var uri = Uri.parse(url);

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError("invalid url, must start with 'http://' or 'https://' sheme (e.g. 'http://example.com')");
    }

    String hostname = getHostname(url);
    headers = await _constructRequestHeaders(hostname, headers);
    dynamic requestBody;

    if (body != null && json != null) {
      throw ArgumentError('cannot use both "json" and "body" choose only one.');
    }

    if (json != null) {
      body = json;
      bodyEncoding = RequestBodyEncoding.JSON;
    }

    if (body != null) {
      String contentTypeHeader;

      if (bodyEncoding == RequestBodyEncoding.JSON) {
        requestBody = Common.toJson(body);
        contentTypeHeader = "application/json";
      }
      else if (bodyEncoding == RequestBodyEncoding.FormURLEncoded) {
        requestBody = Common.encodeMap(body);
        contentTypeHeader = "application/x-www-form-urlencoded";
      }
      else if (bodyEncoding == RequestBodyEncoding.PlainText) {
        requestBody = body;
        contentTypeHeader = "text/plain";
      }
      else {
        throw Exception('unsupported bodyEncoding "$bodyEncoding"');
      }

      if (contentTypeHeader != null && !Common.hasKeyIgnoreCase(headers, "content-type")) {
        headers["content-type"] = contentTypeHeader;
      }
    }

    method = method.toUpperCase();
    var request = http.Request(method, uri);
    if (method == HTTP_METHOD_POST.toUpperCase() || method == HTTP_METHOD_PUT.toUpperCase()) {
      request.body = requestBody;
    }
    request.headers.addAll(headers);
    request.followRedirects = false;
    var future = client.send(request);

    var rawResponse = await future.timeout(Duration(seconds: options.timeoutSeconds));
    var response = await _handleHttpResponse(hostname, rawResponse, options.persistCookies);
    if (rawResponse.isRedirect && options.followRedirects) {
      response = await _handleRedirect(request, rawResponse, bodyEncoding: bodyEncoding, json: json, body: body, headers: headers, client: client, options: options);
    }
    return response;
  }

  static http.Client _createHttpClient(http.Client client, verify) {
    if (client == null) {
      if (!verify) {
        // Ignore SSL errors
        var ioClient = HttpClient();
        ioClient.badCertificateCallback = (_, __, ___) => true;
        client = io_client.IOClient(ioClient);
      } else {
        // The default client validates SSL certificates and fail if invalid
        client = http.Client();
      }
    }
    return client;
  }

  static Future<Response> _handleRedirect(http.Request request, http.StreamedResponse sourceResponse, {body, json, bodyEncoding, http.Client client, headers, RequestOptions options = DEFAULT_REQUEST_OPTIONS}) async {
    var resp;
    if (sourceResponse.statusCode == 308 || sourceResponse.statusCode == 307) {  // re-send original request to new location
      resp = await _httpRequest(request.method, sourceResponse.headers["location"], body: body, json: json, bodyEncoding: bodyEncoding, client: client, headers: headers, options: options);
    } else {  // send GET request
      resp = await _httpRequest(HTTP_METHOD_GET, sourceResponse.headers["location"], body: body, json: json, bodyEncoding: bodyEncoding, client: client, headers: headers, options: options);
    }

    return resp;
  }
}

class RequestOptions {
  final bool followRedirects;
  final int maxRedirects;
  final bool verifySSL;
  final int timeoutSeconds;
  final bool persistCookies;

  const RequestOptions({this.followRedirects = true,
                        this.maxRedirects = 5,
                        this.verifySSL = true,
                        this.timeoutSeconds = 10,
                        this.persistCookies = true
  });
}
// shorthand:
RequestOptions O({followRedirects = true, maxRedirects = 5, verifySSL = true, timeoutSeconds = 10, persistCookies = true}) => RequestOptions(followRedirects: followRedirects, maxRedirects: maxRedirects, verifySSL: verifySSL, timeoutSeconds: timeoutSeconds, persistCookies: persistCookies);
