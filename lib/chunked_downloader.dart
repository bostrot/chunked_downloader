library chunked_downloader;

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';

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
  final String fileName;
  final String savedDir;
  final int chunkSize;
  final ProgressCallback? onProgress;
  final OnDoneCallback? onDone;
  final OnErrorCallback? onError;
  final Function? onCancel;
  final Function? onPause;
  final Function? onResume;
  StreamSubscription<StreamedResponse>? stream;
  ChunkedStreamReader<int>? reader;
  double speed = 0;
  bool paused = false;
  bool done = false;

  ChunkedDownloader({
    required this.url,
    required this.saveFilePath,
    required this.savedDir,
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
    // Download file
    try {
      int offset = 0;
      var httpClient = http.Client();
      var request = http.Request('GET', Uri.parse(url));
      var response = httpClient.send(request);

      // Open file
      File file = File('$saveFilePath.tmp');

      stream = response.asStream().listen(null);
      stream?.onData((http.StreamedResponse r) async {
        // Get file size
        int fileSize = int.parse(r.headers['content-length'] ?? '-1');
        reader = ChunkedStreamReader(r.stream);
        try {
          Uint8List buffer;
          do {
            // TODO: better pausing
            while (paused) {
              await Future.delayed(const Duration(milliseconds: 500));
            }
            // Set start time for speed calculation
            int startTime = DateTime.now().millisecondsSinceEpoch;

            // Read chunk
            buffer = await reader!.readBytes(chunkSize);

            // Calculate speed
            int endTime = DateTime.now().millisecondsSinceEpoch;
            int timeDiff = endTime - startTime;
            speed = (buffer.length / timeDiff) * 1000;

            // Add buffer to chunks list
            offset += buffer.length;
            if (kDebugMode) {
              print('Downloading $fileName ${offset ~/ 1024 ~/ 1024}MB '
                  'Speed: ${speed ~/ 1024 ~/ 1024}MB/s');
            }
            if (onProgress != null) {
              onProgress!(offset, fileSize, speed);
            }
            // Write buffer to disk
            await file.writeAsBytes(buffer, mode: FileMode.append);
          } while (buffer.length == chunkSize);

          // Rename file from .tmp to non-tmp extension
          await file.rename('$savedDir/$fileName');

          // Send done callback
          done = true;
          if (onDone != null) {
            onDone!(File('$savedDir/$fileName'));
          }
          if (kDebugMode) {
            print('Downloaded $fileName');
          }
        } catch (e) {
          if (kDebugMode) {
            print(e);
          }
        } finally {
          reader?.cancel();
          stream?.cancel();
        }
      });
    } catch (error) {
      if (kDebugMode) {
        print('Error downloading: $error');
      }
      if (onError != null) {
        onError!(error);
      }
    }
    return this;
  }

  /// Stop the download
  void stop() {
    stream?.cancel();
    reader?.cancel();
    if (onCancel != null) {
      onCancel!();
    }
  }

  /// Pause the download
  void pause() {
    paused = true;
    if (onPause != null) {
      onPause!();
    }
  }

  /// Resume the download
  void resume() {
    paused = false;
    if (onResume != null) {
      onResume!();
    }
  }
}
