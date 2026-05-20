import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PluginDocsScreen extends StatefulWidget {
  const PluginDocsScreen({super.key});

  @override
  State<PluginDocsScreen> createState() => _PluginDocsScreenState();
}

class _PluginDocsScreenState extends State<PluginDocsScreen> {
  InAppWebViewController? _controller;
  bool _loading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252526),
        foregroundColor: const Color(0xFFCCCCCC),
        title: const Text('Plugin API Reference', style: TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 20),
            tooltip: 'Scroll to top',
            onPressed: () => _controller?.scrollTo(x: 0, y: 0, animated: true),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialFile: 'assets/plugin-docs.html',
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              disableHorizontalScroll: false,
              cacheEnabled: true,
              cacheMode: CacheMode.LOAD_DEFAULT,
            ),
            onWebViewCreated: (c) => _controller = c,
            onLoadStop: (c, url) => setState(() => _loading = false),
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF007ACC)),
            ),
        ],
      ),
    );
  }
}
