import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../sftp_session_manager.dart';
import 'media_extensions.dart';
import 'media_shared.dart';
import 'sftp_stream_server.dart';

class SftpVideoPlayerPage extends StatefulWidget {
  const SftpVideoPlayerPage({
    super.key,
    required this.manager,
    required this.remotePath,
    required this.entry,
  });

  final SftpSessionManager manager;
  final String remotePath;
  final SftpFileEntry entry;

  @override
  State<SftpVideoPlayerPage> createState() => _SftpVideoPlayerPageState();
}

class _SftpVideoPlayerPageState extends State<SftpVideoPlayerPage> {
  SftpStreamServer? _streamServer;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  Object? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _disposed = true;
    _chewieController?.dispose();
    final video = _videoController;
    final server = _streamServer;
    _videoController = null;
    _streamServer = null;
    // Tear down asynchronously; we do not await here because dispose is sync.
    unawaited(() async {
      try {
        await video?.dispose();
      } catch (_) {}
      try {
        await server?.stop();
      } catch (_) {}
    }());
    super.dispose();
  }

  Future<void> _prepare() async {
    final server = SftpStreamServer(
      manager: widget.manager,
      remotePath: widget.remotePath,
      fileName: widget.entry.name,
    );
    try {
      final url = await server.start();
      if (_disposed) {
        await server.stop();
        return;
      }
      _streamServer = server;
      final videoController = VideoPlayerController.networkUrl(url);
      await videoController.initialize();
      if (_disposed) {
        await videoController.dispose();
        return;
      }
      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowPlaybackSpeedChanging: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.white,
          handleColor: Colors.white,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),
        placeholder: const ColoredBox(color: SftpMediaPalette.mediaSurface),
        errorBuilder: (context, errorMessage) {
          final l = AppLocalizations.of(context);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l.trf('media.videoLoadFailed', [errorMessage]),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        },
      );
      if (!mounted) {
        chewieController.dispose();
        await videoController.dispose();
        await server.stop();
        return;
      }
      setState(() {
        _videoController = videoController;
        _chewieController = chewieController;
      });
    } catch (error) {
      await server.stop();
      if (!mounted) return;
      setState(() {
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: SftpMediaPalette.surface,
      body: SafeArea(
        child: Column(
          children: [
            SftpMediaTopBar(
              title: widget.entry.name,
              subtitle: parentDirOf(widget.remotePath),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: SftpMediaPalette.mediaSurface,
                child: _buildMediaArea(l),
              ),
            ),
            SftpMediaInfoCard(
              format: mediaExtension(widget.entry.name) ?? '-',
              size: widget.entry.size,
              modifyTime: widget.entry.modifyTime,
              path: widget.remotePath,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaArea(AppLocalizations l) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.trf('media.videoLoadFailed', [_error.toString()]),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final chewie = _chewieController;
    if (chewie == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l.tr('media.preparingVideo'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Chewie(controller: chewie);
  }
}
