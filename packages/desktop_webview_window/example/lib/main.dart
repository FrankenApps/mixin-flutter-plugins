import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main(List<String> args) {
  debugPrint('args: $args');
  WidgetsFlutterBinding.ensureInitialized();
  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final TextEditingController _controller = TextEditingController(
    text: 'https://example.com',
  );

  bool? _webviewAvailable;

  @override
  void initState() {
    super.initState();
    WebviewWindow.isWebviewAvailable().then((value) {
      setState(() {
        _webviewAvailable = value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
          actions: [
            IconButton(
              onPressed: () async {
                final webview = await WebviewWindow.create(
                  configuration: CreateConfiguration(
                    windowHeight: 1280,
                    windowWidth: 720,
                    title: "ExampleTestWindow",
                    titleBarTopPadding: Platform.isMacOS ? 20 : 0,
                    userDataFolderWindows: await _getWebViewPath(),
                  ),
                );

                webview
                  ..registerJavaScriptMessageHandler("test", (name, body) {
                    debugPrint('on javaScipt message: $name $body');
                  })
                  ..setApplicationNameForUserAgent(" WebviewExample/1.0.0")
                  ..setPromptHandler((prompt, defaultText) {
                    if (prompt == "test") {
                      return "Hello World!";
                    } else if (prompt == "init") {
                      return "initial prompt";
                    }
                    return "";
                  })
                  ..addScriptToExecuteOnDocumentCreated("""
  const mixinContext = {
    platform: 'Desktop',
    conversation_id: 'conversationId',
    immersive: false,
    app_version: '1.0.0',
    appearance: 'dark',
  }
  window.MixinContext = {
    getContext: function() {
      return JSON.stringify(mixinContext)
    }
  }
""")
                  ..launch("http://localhost:3000/test.html");
              },
              icon: const Icon(Icons.bug_report),
            )
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TextField(controller: _controller),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _webviewAvailable != true ? null : _onTap,
                  child: const Text('Open'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _webviewAvailable != true
                      ? null
                      : _runPostNavigationSample,
                  child: const Text('Run POST navigation sample'),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () async {
                    await WebviewWindow.clearAll(
                      userDataFolderWindows: await _getWebViewPath(),
                    );
                    debugPrint('clear complete');
                  },
                  child: const Text('Clear all'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTap() async {
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        userDataFolderWindows: await _getWebViewPath(),
        titleBarTopPadding: Platform.isMacOS ? 20 : 0,
      ),
    );

    final timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final cookies = await webview.getAllCookies();

        if (cookies.isEmpty) {
          debugPrint('⚠️ no cookies found');
        }

        for (final cookie in cookies) {
          debugPrint('cookie: ${cookie.toJson()}');
        }
      } catch (e, stack) {
        debugPrint('getAllCookies error: $e');
        debugPrintStack(stackTrace: stack);
      }
    });

    webview
      ..setBrightness(Brightness.dark)
      ..setApplicationNameForUserAgent(" WebviewExample/1.0.0")
      ..launch(_controller.text)
      ..setOnUrlRequestCallback((url) {
        debugPrint('url: $url');
        final uri = Uri.parse(url);
        if (uri.path == '/login_success') {
          debugPrint('login success. token: ${uri.queryParameters['token']}');
          webview.close();
        }
        // grant navigation request
        return true;
      })
      ..openDevToolsWindow()
      ..onClose.whenComplete(() {
        debugPrint("on close");
        timer.cancel();
      });
    await Future.delayed(const Duration(seconds: 2));
    for (final javaScript in _javaScriptToEval) {
      try {
        final ret = await webview.evaluateJavaScript(javaScript);
        debugPrint('evaluateJavaScript: $ret');
      } catch (e) {
        debugPrint('evaluateJavaScript error: $e \n $javaScript');
      }
    }
  }

  Future<void> _runPostNavigationSample() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final requestBody = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.html;

      if (request.uri.path == '/' && request.method == 'GET') {
        request.response.write('''
          <!doctype html>
          <meta charset="utf-8">
          <title>POST navigation sample</title>
          <h1>POST navigation sample</h1>
          <p>Submit this form to send a POST request through the WebView.</p>
          <form method="POST" action="/submit">
            <input type="hidden" name="message" value="hello-webview">
            <button type="submit">Send POST request</button>
          </form>
        ''');
      } else if (request.uri.path == '/submit') {
        final succeeded = request.method == 'POST' &&
            requestBody == 'message=hello-webview';
        debugPrint(
          'POST sample received ${request.method} ${request.uri.path}: '
          '$requestBody',
        );
        request.response.statusCode =
            succeeded ? HttpStatus.ok : HttpStatus.badRequest;
        request.response.write('''
          <!doctype html>
          <meta charset="utf-8">
          <h1 style="color: ${succeeded ? 'green' : 'red'}">
            ${succeeded ? 'POST request succeeded' : 'POST request failed'}
          </h1>
          <p>Method received: ${request.method}</p>
          <p>Body received: $requestBody</p>
          <p>Expected: POST with body message=hello-webview</p>
        ''');
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not found');
      }
      await request.response.close();
    });

    try {
      final webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: 'POST request sample',
          userDataFolderWindows: await _getWebViewPath(),
          titleBarTopPadding: Platform.isMacOS ? 20 : 0,
        ),
      );
      webview
        ..setOnUrlRequestCallback((url) {
          debugPrint('POST sample navigation requested: $url');
          return true;
        })
        ..launch('http://127.0.0.1:${server.port}/')
        ..onClose.whenComplete(() async {
          await server.close(force: true);
        });
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }
}

const _javaScriptToEval = [
  """
  function test() {
    return;
  }
  test();
  """,
  'eval({"name": "test", "user_agent": navigator.userAgent})',
  '1 + 1',
  'undefined',
  '1.0 + 1.0',
  '"test"',
];

Future<String> _getWebViewPath() async {
  final document = await getApplicationDocumentsDirectory();
  return p.join(
    document.path,
    'desktop_webview_window',
  );
}
