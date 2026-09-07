// ignore_for_file: avoid_print

import 'package:chunked_downloader/chunked_downloader.dart';

ChunkedDownloader? chunkedDownloader;

void downloadImage() async {
  chunkedDownloader = await ChunkedDownloader(
      url: 'https://filesamples.com/samples/video/mjpeg/sample_3840x2160.mjpeg',
      saveFilePath: '/tmp/test.mjpeg',
      chunkSize: 1024 * 1024,
      onProgress: (received, total, speed) {
        if (total != -1) {
          print('${(received / total * 100).toStringAsFixed(0)}%');
        } else {
          print('${(received / 1024 / 1024).toStringAsFixed(0)}MB ');
        }
        print('${(speed / 1024 / 1024).toStringAsFixed(2)} MB/s');
      },
      onError: (error) {
        print('Download failed: $error');
      },
      onDone: (file) {
        print('Download is done!');
      }).start();
}

void main() {
  downloadImage();
}
