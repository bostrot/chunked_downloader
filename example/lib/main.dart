import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:chunked_downloader/chunked_downloader.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var status = 'Hello World';
  ChunkedDownloader? chunkedDownloader;

  void downloadImage() async {
    chunkedDownloader = await ChunkedDownloader(
        url:
            'https://filesamples.com/samples/video/mjpeg/sample_3840x2160.mjpeg',
        savedDir: '/temp',
        chunkSize: 1024 * 1024,
        fileName: 'deletemeshawn.mjpeg',
        onProgress: (received, total, speed) {
          status = '';
          if (total != -1) {
            status += '${(received / total).toStringAsFixed(0)}% ';
            if (kDebugMode) {
              print('${(received / total * 100).toStringAsFixed(0)}%');
            }
          } else {
            status += '${(received / ~1024 / ~1024).toStringAsFixed(0)}MB ';
          }
          setState(() {
            status += '${(speed / ~1024 / ~1024).toStringAsFixed(2)} MB/s';
          });
        },
        onDone: (file) {
          if (kDebugMode) {
            print('Download is done!');
          }
          setState(() {
            status = 'Download is done! ${file.path}';
          });
        }).start();
  }

  @override
  void initState() {
    downloadImage();
    super.initState();
  }

  // on destroy

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
          child: Column(
        children: [
          Text(status),
          TextButton(
              onPressed: () {
                chunkedDownloader?.stop();
              },
              child: const Text("cancel")),
          TextButton(
              onPressed: () {
                chunkedDownloader?.pause();
              },
              child: const Text("pause")),
          TextButton(
              onPressed: () {
                chunkedDownloader?.resume();
              },
              child: const Text("continue")),
        ],
      )),
    );
  }
}
