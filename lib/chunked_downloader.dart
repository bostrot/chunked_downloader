library chunked_downloader;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:http/http.dart' as http;

/// Progress Callback
/// [progress] is the current progress in bytes
/// [total] is the total size of the file in bytes
typedef ProgressCallback = void Function(int progress, int total, double speed);

/// On Done Callback
/// [file] is the downloaded file
typedef OnDoneCallback = void Function(File file);

/// On Error Callback
/// [error] is the error that occured
typedef OnErrorCallback = void Function(dynamic error);

/// Void Callback
typedef VoidCallback = void Function();

/// Custom Downloader with ChunkSize
///
/// [chunkSize] is the size of each chunk in bytes
///
/// [onProgress] is the callback function that will be called when the download is in progress
///
/// [onDone] is the callback function that will be called when the download is done
///
/// [onError] is the callback function that will be called when the download is failed
///
/// [onCancel] is the callback function that will be called when the download is canceled
///
/// [onPause] is the callback function that will be called when the download is paused
///
/// [onResume] is the callback function that will be called when the download is resumed
///
class ChunkedDownloader {
  final String url;
  final String saveFilePath;
  final int chunkSize;
  final ProgressCallback? onProgress;
  final OnDoneCallback? onDone;
  final OnErrorCallback? onError;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  ChunkedStreamReader<int>? reader;
  Map<String, String>? headers;
  double speed = 0;
  bool paused = false;
  bool done = false;
  bool _cancelled = false;
  static const bool kDebugMode = false;

  // Better pausing mechanism
  Completer<void>? _pauseCompleter;
  http.Client? _httpClient;

  ChunkedDownloader({
    required this.url,
    required this.saveFilePath,
    this.headers,
    this.chunkSize = 1024 * 1024, // 1 MB
    this.onProgress,
    this.onDone,
    this.onError,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

  /// Start the download
  /// @result {Future<ChunkedDownloader>} the current instance of the downloader
  Future<ChunkedDownloader> start() async {
    if (done || _cancelled) {
      throw StateError('Download already completed or cancelled');
    }

    try {
      int offset = 0;
      _httpClient = http.Client();
      var request = http.Request('GET', Uri.parse(url));

      // Set headers
      if (headers != null) {
        request.headers.addAll(headers!);
      }

      var response = await _httpClient!.send(request);

      // Check for HTTP errors
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      // Create directory if it doesn't exist
      File file = File('$saveFilePath.tmp');
      await file.parent.create(recursive: true);

      // Get file size directly from response
      int fileSize = response.contentLength ?? -1;
      reader = ChunkedStreamReader(response.stream);

      try {
        Uint8List buffer;
        do {
          // Check if cancelled
          if (_cancelled) {
            break;
          }

          // Better pausing mechanism - wait for resume if paused
          if (paused && _pauseCompleter != null) {
            await _pauseCompleter!.future;
          }

          // Check again after potential pause
          if (_cancelled) {
            break;
          }

          // Set start time for speed calculation
          int startTime = DateTime.now().millisecondsSinceEpoch;

          // Read chunk with timeout
          buffer = await reader!.readBytes(chunkSize);

          // Calculate speed (bytes per second)
          int endTime = DateTime.now().millisecondsSinceEpoch;
          int timeDiff = endTime - startTime;
          if (timeDiff > 0) {
            speed = (buffer.length / timeDiff) * 1000;
          }

          offset += buffer.length;
          if (kDebugMode) {
            print('Downloading ${(offset / (1024 * 1024)).toStringAsFixed(2)}MB '
                'Speed: ${(speed / (1024 * 1024)).toStringAsFixed(2)}MB/s');
          }

          if (onProgress != null) {
            onProgress!(offset, fileSize, speed);
          }

          // Write buffer to disk
          await file.writeAsBytes(buffer, mode: FileMode.append);
        } while (buffer.length == chunkSize && !_cancelled);

        if (!_cancelled) {
          // Rename file from .tmp to final name
          await file.rename(saveFilePath);

          // Send done callback
          done = true;
          if (onDone != null) {
            onDone!(File(saveFilePath));
          }
          if (kDebugMode) {
            print('Download completed successfully.');
          }
        } else {
          // Clean up temp file if cancelled
          if (await file.exists()) {
            await file.delete();
          }
        }
      } catch (error) {
        if (kDebugMode) {
          print('Error during download: $error');
        }

        // Clean up temp file on error
        if (await File('$saveFilePath.tmp').exists()) {
          await File('$saveFilePath.tmp').delete();
        }

        if (onError != null) {
          onError!(error);
        }
        rethrow;
      } finally {
        await reader?.cancel();
        _httpClient?.close();
        _httpClient = null;
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error starting download: $error');
      }
      if (onError != null) {
        onError!(error);
      }
      rethrow;
    }
    return this;
  }

  /// Stop the download
  void stop() {
    _cancelled = true;
    reader?.cancel();
    _httpClient?.close();

    // Complete any pending pause to avoid hanging
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }

    if (onCancel != null) {
      onCancel!();
    }
  }

  /// Pause the download
  void pause() {
    if (!paused) {
      paused = true;
      _pauseCompleter = Completer<void>();
      if (onPause != null) {
        onPause!();
      }
    }
  }

  /// Resume the download
  void resume() {
    if (paused) {
      paused = false;
      if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
        _pauseCompleter!.complete();
      }
      _pauseCompleter = null;
      if (onResume != null) {
        onResume!();
      }
    }
  }
}
