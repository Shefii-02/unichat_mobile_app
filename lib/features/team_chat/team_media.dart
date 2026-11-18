import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

/// On-device store for chat media. First view downloads the file into the app's documents folder; every
/// later view checks that folder first and only downloads again if the file is missing (cleared storage,
/// reinstall…). Keyed by URL, so the same file shared twice is stored once.
class TeamMediaCache {
  TeamMediaCache._();
  static final _dio = Dio();
  static final _inflight = <String, Future<File>>{};
  static Directory? _dir;

  static Future<Directory> _root() async {
    if (_dir != null && await _dir!.exists()) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    _dir = await Directory('${base.path}/team_chat_media').create(recursive: true);
    return _dir!;
  }

  static String _name(String url, String? name) {
    final ext = _ext(name ?? Uri.tryParse(url)?.path ?? '');
    return '${md5.convert(url.codeUnits)}$ext';
  }

  static String _ext(String s) {
    final i = s.lastIndexOf('.');
    return i > 0 && s.length - i <= 6 ? s.substring(i) : '';
  }

  /// The local copy if it exists, else null (no network).
  static Future<File?> cached(String url, {String? name}) async {
    final f = File('${(await _root()).path}/${_name(url, name)}');
    return await f.exists() && await f.length() > 0 ? f : null;
  }

  /// Live progress (0..1, 0 while the size is unknown) of the download for this file, or null when none is running.
  /// Lives here, not in a bubble's State, so a bubble rebuilt mid-download (new message, socket refresh) still shows it.
  static final _progress = <String, ValueNotifier<double>>{};
  static ValueNotifier<double>? watch(String url, {String? name}) => _progress[_name(url, name)];

  /// Bumped whenever a download finishes, so bubbles re-check whether their file is now on the device.
  static final done = ValueNotifier<int>(0);

  /// Local copy, downloading it first when missing. [onProgress] gets 0..1.
  static Future<File> fetch(String url, {String? name, void Function(double)? onProgress}) async {
    final hit = await cached(url, name: name);
    if (hit != null) return hit;
    final key = _name(url, name);
    final n = _progress.putIfAbsent(key, () => ValueNotifier<double>(0));
    n.addListener(() => onProgress?.call(n.value));
    return _inflight[key] ??= _download(url, key, n).whenComplete(() {
      _inflight.remove(key);
      _progress.remove(key);
      done.value++;
    });
  }

  static Future<File> _download(String url, String key, ValueNotifier<double> progress) async {
    final dest = File('${(await _root()).path}/$key');
    final tmp = File('${dest.path}.part');
    await _dio.download(url, tmp.path, onReceiveProgress: (r, t) { if (t > 0) progress.value = r / t; });
    return tmp.rename(dest.path);
  }

  /// Total size of the cache folder (for a "storage" row if wanted).
  static Future<int> sizeBytes() async {
    var n = 0;
    await for (final e in (await _root()).list()) {
      if (e is File) n += await e.length();
    }
    return n;
  }

  static Future<void> clear() async {
    final d = await _root();
    if (await d.exists()) { await d.delete(recursive: true); _dir = null; }
  }
}

/// Progress-aware "download then show" wrapper: shows a ring while fetching, then [builder] with the local file.
class CachedFileBuilder extends StatefulWidget {
  const CachedFileBuilder({super.key, required this.url, this.name, required this.builder});
  final String url;
  final String? name;
  final Widget Function(BuildContext, File) builder;
  @override
  State<CachedFileBuilder> createState() => _CachedFileBuilderState();
}

class _CachedFileBuilderState extends State<CachedFileBuilder> {
  File? _file;
  double _p = 0;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await TeamMediaCache.fetch(widget.url, name: widget.name, onProgress: (p) { if (mounted) setState(() => _p = p); });
      if (mounted) setState(() => _file = f);
    } catch (e) {
      if (mounted) setState(() => _err = 'Download failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_file != null) return widget.builder(context, _file!);
    if (_err != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 40),
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: Colors.white70)),
          TextButton(onPressed: () { setState(() { _err = null; _p = 0; }); _load(); }, child: const Text('Retry')),
        ]),
      );
    }
    return Center(
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(width: 56, height: 56, child: CircularProgressIndicator(value: _p > 0 ? _p : null, color: Colors.white)),
        const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 22),
      ]),
    );
  }
}

/// A shared photo / video entry for the full-screen gallery.
class MediaItem {
  const MediaItem({required this.url, required this.isVideo, this.name, this.sender, this.time});
  final String url;
  final bool isVideo;
  final String? name, sender, time;
}

/// Full-screen swipeable gallery of photos and videos (WhatsApp style): pinch-zoom images, video with
/// controls, share. Each item is fetched into the local cache the first time it is opened.
class MediaGalleryPage extends StatefulWidget {
  const MediaGalleryPage({super.key, required this.items, this.initialIndex = 0});
  final List<MediaItem> items;
  final int initialIndex;
  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage> {
  late final PageController _pc = PageController(initialPage: widget.initialIndex);
  late int _i = widget.initialIndex;
  bool _chrome = true;

  Future<void> _share() async {
    final it = widget.items[_i];
    try {
      final f = await TeamMediaCache.fetch(it.url, name: it.name);
      await Share.shareXFiles([XFile(f.path)]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.items[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chrome
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.sender ?? 'Media', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (it.time != null) Text(it.time!, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
              ]),
              actions: [IconButton(icon: const Icon(Icons.share_rounded), onPressed: _share)],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: PhotoViewGallery.builder(
          pageController: _pc,
          itemCount: widget.items.length,
          onPageChanged: (i) => setState(() => _i = i),
          scrollPhysics: const BouncingScrollPhysics(),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          builder: (context, index) {
            final m = widget.items[index];
            if (m.isVideo) {
              return PhotoViewGalleryPageOptions.customChild(
                child: _VideoPage(item: m),
                disableGestures: true,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.contained,
              );
            }
            return PhotoViewGalleryPageOptions.customChild(
              child: CachedFileBuilder(
                url: m.url,
                name: m.name,
                builder: (_, f) => PhotoView(imageProvider: FileImage(f), backgroundDecoration: const BoxDecoration(color: Colors.black)),
              ),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
            );
          },
        ),
      ),
    );
  }
}

class _VideoPage extends StatelessWidget {
  const _VideoPage({required this.item});
  final MediaItem item;
  @override
  Widget build(BuildContext context) =>
      CachedFileBuilder(url: item.url, name: item.name, builder: (_, f) => _LocalVideo(file: f));
}

class _LocalVideo extends StatefulWidget {
  const _LocalVideo({required this.file});
  final File file;
  @override
  State<_LocalVideo> createState() => _LocalVideoState();
}

class _LocalVideoState extends State<_LocalVideo> {
  late final VideoPlayerController _c = VideoPlayerController.file(widget.file)
    ..initialize().then((_) { if (mounted) { setState(() {}); _c.play(); } })
    ..addListener(() { if (mounted) setState(() {}); });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _f(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (!_c.value.isInitialized) return const Center(child: CircularProgressIndicator(color: Colors.white));
    final v = _c.value;
    return Stack(alignment: Alignment.center, children: [
      AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c)),
      GestureDetector(
        onTap: () => v.isPlaying ? _c.pause() : _c.play(),
        child: AnimatedOpacity(
          opacity: v.isPlaying ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          child: const CircleAvatar(radius: 32, backgroundColor: Colors.black54, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 42)),
        ),
      ),
      Positioned(
        left: 12, right: 12, bottom: 24,
        child: Row(children: [
          Text(_f(v.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
          Expanded(child: VideoProgressIndicator(_c, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 10))),
          Text(_f(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    ]);
  }
}

/// In-app PDF viewer (downloads to the local cache first). Pages scroll vertically, pinch to zoom.
class PdfViewerPage extends StatelessWidget {
  const PdfViewerPage({super.key, required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: () async {
                final f = await TeamMediaCache.fetch(url, name: name);
                await Share.shareXFiles([XFile(f.path)]);
              },
            ),
          ],
        ),
        backgroundColor: Colors.grey.shade300,
        body: FutureBuilder<File>(
          future: TeamMediaCache.fetch(url, name: name),
          builder: (_, s) {
            if (s.hasError) return const Center(child: Text('Could not open this PDF'));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            return PdfPreview(
              build: (_) => s.data!.readAsBytes(),
              useActions: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowPrinting: false,
              allowSharing: false,
              scrollViewDecoration: BoxDecoration(color: Colors.grey.shade300),
              pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white),
            );
          },
        ),
      );
}

/// Opens any shared file: PDF in the in-app viewer, everything else via the system share / open-with sheet
/// once it is on the device.
Future<void> openTeamFile(BuildContext context, {required String url, required String name, String? mime}) async {
  final isPdf = (mime ?? '').contains('pdf') || name.toLowerCase().endsWith('.pdf');
  if (isPdf) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerPage(url: url, name: name)));
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  try {
    final f = await TeamMediaCache.fetch(url, name: name);
    await Share.shareXFiles([XFile(f.path)]);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not open this file')));
  }
}

/// Image thumbnail that prefers the on-device copy, falls back to the network, and saves it locally in the
/// background so the next load is instant and works offline.
class CachedChatImage extends StatefulWidget {
  const CachedChatImage({super.key, required this.url, this.name, this.width = 220});
  final String url;
  final String? name;
  final double width;
  @override
  State<CachedChatImage> createState() => _CachedChatImageState();
}

class _CachedChatImageState extends State<CachedChatImage> {
  File? _local;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    TeamMediaCache.cached(widget.url, name: widget.name).then((f) {
      if (!mounted) return;
      setState(() { _local = f; _checked = true; });
      if (f == null) {
        // Save it on the device in the background so the next load is instant and works offline.
        TeamMediaCache.fetch(widget.url, name: widget.name).then<void>((n) { if (mounted) setState(() => _local = n); }, onError: (_) {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_local != null && _local!.path.isNotEmpty) {
      return Image.file(_local!, width: widget.width, fit: BoxFit.cover);
    }
    if (!_checked) return SizedBox(width: widget.width, height: 160);
    return CachedNetworkImage(
      imageUrl: widget.url,
      width: widget.width,
      fit: BoxFit.cover,
      placeholder: (_, __) => SizedBox(width: widget.width, height: 160, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
      errorWidget: (_, __, ___) => SizedBox(width: widget.width, height: 100, child: Icon(Icons.broken_image_rounded, color: context.mutedColor)),
    );
  }
}
