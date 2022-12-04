Dart downloader that lets you set a custom chunk sizes for a lot faster downloads.

## Features

* custom chunk size downloads
* stop downloads
* pause downloads
* resume downloads

## Getting started

Add this package to your pubspec.yml:

    chunked_downloader: x.x.x

## Usage

You can use it like this: (note that everything is in bytes)

```dart
    var chunkedDownloader = await ChunkedDownloader(
        url: 'https://filesamples.com/samples/video/mjpeg/sample_3840x2160.mjpeg',
        savedDir: '/temp',
        fileName: 'sometestfile.mjpeg',
        chunkSize: 1024 * 1024,
        onError: (error) {},
        onProgress: (received, total, speed) {},
        onDone: (file) {})
    .start();

chunkedDownloader.pause();
chunkedDownloader.resume();
chunkedDownloader.stop();
```
