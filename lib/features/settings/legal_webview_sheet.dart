import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

/// Shows [title] (loaded from [url]) in a near-full-height modal bottom sheet with an
/// embedded webview — used for Privacy Policy / Terms of Service.
///
/// NOTE: [url] here is a placeholder (teamzo.io/legal/...) pending the real hosted pages —
/// swap it for the actual URL once available.
void showLegalSheet(BuildContext context, {required String title, required String url}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: ctx.lineColor, borderRadius: BorderRadius.circular(4)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _LegalWebView(url: url)),
        ],
      ),
    ),
  );
}

class _LegalWebView extends StatefulWidget {
  const _LegalWebView({required this.url});
  final String url;
  @override
  State<_LegalWebView> createState() => _LegalWebViewState();
}

class _LegalWebViewState extends State<_LegalWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (e) => setState(() { _loading = false; _error = e.description; }),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_error == null) WebViewWidget(controller: _controller),
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text("Couldn't load this page. Check your connection and try again.\n($_error)",
                  textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor)),
            ),
          ),
        if (_loading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
