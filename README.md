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
        saveFilePath: '/tmp/sometestfile.mjpeg',
        chunkSize: 1024 * 1024,
        headers: {'Authorization': 'Bearer token'},
        onError: (error) {},
        onProgress: (received, total, speed) {},
        onDone: (file) {})
    .start();

chunkedDownloader.pause();
chunkedDownloader.resume();
chunkedDownloader.stop();
```

The download is written to `<saveFilePath>.tmp` first and only renamed to
`saveFilePath` once it completed, so a cancelled or failed download never
leaves a half written file behind.

## Releasing

Pushing a `v<version>` tag that matches the version in `pubspec.yaml` runs
`.github/workflows/publish.yml`, which analyzes, tests and dry runs the package
before publishing it to pub.dev.

The workflow authenticates with the `PUB_CREDENTIALS` repository secret — the
contents of the local `pub-credentials.json` written by `dart pub login`. When
the secret is unset it falls back to the pub.dev OIDC token, which needs
automated publishing to be configured for the package on pub.dev.
