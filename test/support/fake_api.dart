import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';

/// Return this from a [FakeApi] handler to answer with a status other than 200 (e.g. 409 for "device limit").
class FakeReply {
  const FakeReply(this.status, this.body);
  final int status;
  final dynamic body;
}

/// A stand-in for the Laravel server: every request the app makes goes to [handler], which returns the
/// JSON body to answer with. All requests are kept in [calls] so tests can check what was sent.
class FakeApi implements HttpClientAdapter {
  FakeApi(this.handler);

  final dynamic Function(RequestOptions options) handler;
  final List<RequestOptions> calls = [];

  Iterable<RequestOptions> where(String method, String path) =>
      calls.where((c) => c.method == method && c.path == path);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    final reply = handler(options);
    final status = reply is FakeReply ? reply.status : 200;
    final body = reply is FakeReply ? reply.body : reply;
    return ResponseBody.fromString(jsonEncode(body ?? {}), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}

  /// Point the app's shared HTTP client at this fake. The auth interceptor is dropped because it reads the
  /// secure-storage plugin, which does not exist in a unit-test environment.
  void install() {
    DioClient.laravelDio.interceptors.clear();
    DioClient.laravelDio.httpClientAdapter = this;
  }
}
