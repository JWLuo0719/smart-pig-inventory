import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LocalVideoPlayer extends StatefulWidget {
  const LocalVideoPlayer({required this.file, super.key});
  final File file;
  @override
  State<LocalVideoPlayer> createState() => _LocalVideoPlayerState();
}

class _LocalVideoPlayerState extends State<LocalVideoPlayer> {
  late final VideoPlayerController _controller;
  late final Future<void> _ready;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _ready = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('当前设备无法播放此视频，文件仍保留。'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
              child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller))),
          VideoProgressIndicator(_controller, allowScrubbing: true),
          ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller,
              builder: (context, value, _) => IconButton(
                  tooltip: value.isPlaying ? '暂停' : '播放',
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () => value.isPlaying
                      ? _controller.pause()
                      : _controller.play())),
        ]);
      });
}
