import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../sftp_session_manager.dart';
import 'media_extensions.dart';
import 'media_shared.dart';

class SftpImagePreviewPage extends StatefulWidget {
  SftpImagePreviewPage({
    super.key,
    required this.manager,
    required this.directoryPath,
    required this.images,
    required this.initialIndex,
  }) : assert(images.isNotEmpty, 'images must not be empty'),
       assert(
         initialIndex >= 0 && initialIndex < images.length,
         'initialIndex out of range',
       );

  final SftpSessionManager manager;
  final String directoryPath;
  final List<SftpFileEntry> images;
  final int initialIndex;

  @override
  State<SftpImagePreviewPage> createState() => _SftpImagePreviewPageState();
}

class _SftpImagePreviewPageState extends State<SftpImagePreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;
  final Map<int, _ImageDownloadState> _downloads = {};
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _ensureDownload(_currentIndex);
    _ensureDownload(_currentIndex - 1);
    _ensureDownload(_currentIndex + 1);
  }

  @override
  void dispose() {
    _disposed = true;
    _pageController.dispose();
    super.dispose();
  }

  String _remotePathOf(int index) => SftpSessionManager.joinPath(
    widget.directoryPath,
    widget.images[index].name,
  );

  void _ensureDownload(int index) {
    if (index < 0 || index >= widget.images.length) return;
    if (_downloads.containsKey(index)) return;
    final state = _ImageDownloadState(initialTotal: widget.images[index].size);
    _downloads[index] = state;
    unawaited(_runDownload(index, state));
  }

  Future<void> _runDownload(int index, _ImageDownloadState state) async {
    final entry = widget.images[index];
    try {
      final file = await resolveSftpMediaCacheFile(entry.name);
      await widget.manager.downloadToLocalFile(
        _remotePathOf(index),
        file,
        onProgress: (received, total) {
          if (_disposed || !mounted) return;
          setState(() {
            state.received = received;
            state.total = total ?? state.total;
          });
        },
      );
      if (_disposed || !mounted) return;
      setState(() {
        state.file = file;
      });
    } catch (error) {
      if (_disposed || !mounted) return;
      setState(() {
        state.error = error;
      });
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    _ensureDownload(index);
    _ensureDownload(index - 1);
    _ensureDownload(index + 1);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currentEntry = widget.images[_currentIndex];
    final currentPath = _remotePathOf(_currentIndex);
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            SftpMediaTopBar(
              title: currentEntry.name,
              subtitle: parentDirOf(currentPath),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFF0A0F14),
                child: PhotoViewGallery.builder(
                  pageController: _pageController,
                  itemCount: widget.images.length,
                  onPageChanged: _onPageChanged,
                  scrollPhysics: const BouncingScrollPhysics(),
                  backgroundDecoration: const BoxDecoration(
                    color: Color(0xFF0A0F14),
                  ),
                  builder: (context, index) => _buildPage(l, index),
                ),
              ),
            ),
            SftpMediaInfoCard(
              format: mediaExtension(currentEntry.name) ?? '-',
              size: currentEntry.size,
              modifyTime: currentEntry.modifyTime,
              path: currentPath,
            ),
          ],
        ),
      ),
    );
  }

  PhotoViewGalleryPageOptions _buildPage(AppLocalizations l, int index) {
    final state = _downloads[index];
    if (state == null || state.isLoading) {
      return PhotoViewGalleryPageOptions.customChild(
        child: SftpMediaProgressIndicator(
          received: state?.received ?? 0,
          total: state?.total ?? widget.images[index].size,
        ),
        initialScale: 1.0,
        minScale: 1.0,
        maxScale: 1.0,
      );
    }
    if (state.hasError) {
      return PhotoViewGalleryPageOptions.customChild(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l.trf('media.imageLoadFailed', [state.error.toString()]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
        initialScale: 1.0,
        minScale: 1.0,
        maxScale: 1.0,
      );
    }
    return PhotoViewGalleryPageOptions(
      imageProvider: FileImage(state.file!),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      errorBuilder: (_, error, _) => Center(
        child: Text(
          l.trf('media.imageLoadFailed', [error.toString()]),
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

class _ImageDownloadState {
  _ImageDownloadState({int? initialTotal}) : total = initialTotal;

  File? file;
  Object? error;
  int received = 0;
  int? total;

  bool get isLoading => file == null && error == null;
  bool get hasError => error != null;
}
