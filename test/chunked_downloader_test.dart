import 'dart:async';
import 'dart:io';

import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:test/test.dart';

/// A tiny HTTP server so the tests do not depend on the network.
class _TestServer {
  _TestServer(this._server);

  final HttpServer _server;

  /// Bytes handed out by [/file], one list per write.
  List<List<int>> body = [];

  /// Delay inserted between two writes of [body].
  Duration writeDelay = Duration.zero;

  /// Status code returned by [/file].
  int statusCode = 200;

  /// Headers of the last request that reached the server.
  HttpHeaders? lastRequestHeaders;

  String get url => 'http://${_server.address.host}:${_server.port}/file';

  static Future<_TestServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestServer(server);
    unawaited(testServer._serve());
    return testServer;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      // The client can disappear mid-response (stop(), or the tear down
      // closing the server), which turns every write into an error.
      try {
        lastRequestHeaders = request.headers;
        request.response.statusCode = statusCode;
        if (statusCode == 200) {
          request.response.contentLength = body.fold<int>(
            0,
            (sum, part) => sum + part.length,
          );
          for (final part in body) {
            request.response.add(part);
            await request.response.flush();
            if (writeDelay > Duration.zero) {
              await Future<void>.delayed(writeDelay);
            }
          }
        }
        await request.response.close();
      } catch (_) {
        // Nothing to do, the test asserts on the client side.
      }
    }
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late _TestServer server;
  late Directory tempDir;
  late String savePath;

  setUp(() async {
    server = await _TestServer.start();
    tempDir = await Directory.systemTemp.createTemp('chunked_downloader_test');
    savePath = '${tempDir.path}/download.bin';
  });

  tearDown(() async {
    await server.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  List<List<int>> chunksOf(int chunkCount, int chunkSize) => [
    for (var i = 0; i < chunkCount; i++) List<int>.filled(chunkSize, i % 256),
  ];

  test('downloads a file to the given path', () async {
    server.body = chunksOf(4, 1024);
    File? doneFile;

    final downloader = await ChunkedDownloader(
      url: server.url,
      saveFilePath: savePath,
      chunkSize: 1024,
      onDone: (file) => doneFile = file,
    ).start();

    expect(downloader.done, isTrue);
    expect(doneFile?.path, savePath);
    expect(File(savePath).lengthSync(), 4 * 1024);
    expect(
      File(savePath).readAsBytesSync(),
      server.body.expand((part) => part).toList(),
    );
    expect(File('$savePath.tmp').existsSync(), isFalse);
  });

  test('creates the target directory and reports progress', () async {
    savePath = '${tempDir.path}/nested/dir/download.bin';
    server.body = chunksOf(3, 512);
    final progress = <int>[];
    int? reportedTotal;

    await ChunkedDownloader(
      url: server.url,
      saveFilePath: savePath,
      chunkSize: 512,
      onProgress: (received, total, speed) {
        progress.add(received);
        reportedTotal = total;
      },
    ).start();

    expect(File(savePath).existsSync(), isTrue);
    expect(progress, [512, 1024, 1536, 1536]);
    expect(reportedTotal, 1536);
  });

  test('sends the given headers', () async {
    server.body = chunksOf(1, 16);

    await ChunkedDownloader(
      url: server.url,
      saveFilePath: savePath,
      headers: {'x-test-header': 'chunked'},
    ).start();

    expect(server.lastRequestHeaders?.value('x-test-header'), 'chunked');
  });

  test('does not append to a leftover temp file', () async {
    await File('$savePath.tmp').writeAsBytes(List<int>.filled(2048, 7));
    server.body = chunksOf(2, 256);

    await ChunkedDownloader(
      url: server.url,
      saveFilePath: savePath,
      chunkSize: 256,
    ).start();

    expect(File(savePath).lengthSync(), 512);
  });

  test('reports an http error and leaves no file behind', () async {
    server.statusCode = 404;
    Object? reportedError;

    await expectLater(
      ChunkedDownloader(
        url: server.url,
        saveFilePath: savePath,
        onError: (error) => reportedError = error,
      ).start(),
      throwsA(isA<HttpException>()),
    );

    expect(reportedError, isA<HttpException>());
    expect(File(savePath).existsSync(), isFalse);
    expect(File('$savePath.tmp').existsSync(), isFalse);
  });

  test('reports a connection error for an unreachable host', () async {
    Object? reportedError;
    final unreachable = server.url;
    await server.close();

    await expectLater(
      ChunkedDownloader(
        url: unreachable,
        saveFilePath: savePath,
        onError: (error) => reportedError = error,
      ).start(),
      throwsA(anything),
    );

    expect(reportedError, isNotNull);
    expect(File(savePath).existsSync(), isFalse);
  });

  test('refuses to start twice', () async {
    server.body = chunksOf(1, 32);
    final downloader = ChunkedDownloader(
      url: server.url,
      saveFilePath: savePath,
    );

    await downloader.start();

    expect(downloader.start, throwsA(isA<StateError>()));
  });

  test('stop cancels the download and cleans up', () async {
    server.body = chunksOf(20, 256);
    server.writeDelay = const Duration(milliseconds: 20);
    var cancelled = false;
    final firstChunk = Completer<void>();

    final downloader = ChunkedDownloader(
      url: server.url,
      saveFilePath: savePath,
      chunkSize: 256,
      onCancel: () => cancelled = true,
      onProgress: (received, total, speed) {
        if (!firstChunk.isCompleted) {
          firstChunk.complete();
        }
      },
    );

    final future = downloader.start();
    // Only stop once the download is actually running, otherwise the test
    // would race the request instead of the download loop.
    await firstChunk.future;
    downloader.stop();
    await future;

    expect(cancelled, isTrue);
    expect(downloader.done, isFalse);
    expect(File(savePath).existsSync(), isFalse);
    expect(File('$savePath.tmp').existsSync(), isFalse);
  });

  test('pause holds the download until resume', () async {
    server.body = chunksOf(10, 256);
    server.writeDelay = const Duration(milliseconds: 10);
    var paused = false;
    var resumed = false;
    var received = 0;

    final downloader = ChunkedDownloader(
      url: server.url,
      saveFilePath: savePath,
      chunkSize: 256,
      onPause: () => paused = true,
      onResume: () => resumed = true,
      onProgress: (progress, total, speed) => received = progress,
    );

    final future = downloader.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    downloader.pause();
    expect(paused, isTrue);

    final whilePaused = received;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // At most the chunk that was already in flight may still land.
    expect(received, lessThanOrEqualTo(whilePaused + 256));

    downloader.resume();
    expect(resumed, isTrue);

    await future;
    expect(downloader.done, isTrue);
    expect(File(savePath).lengthSync(), 10 * 256);
  });
}
