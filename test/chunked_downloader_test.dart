import 'dart:io';

import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:test/test.dart';

void main() {
  String img = 'https://storage.googleapis.com/cms-storage-bucket'
      '/a40ceb6e5d342207de7b.png';
  test('downloads a file to a location', () async {
    bool done = false;
    ChunkedDownloader(
        url: img,
        saveFilePath: '/tmp/flutter_image.png',
        onProgress: (received, total, speed) {},
        onDone: (file) {
          done = true;
        }).start();
    // Wait
    while (!done) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    expect(File('/tmp/flutter_image.png').existsSync(), true);
  });
}
