import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

/// SplashPage plays the full-screen video splash screen
/// using assets/video/logoremover_1785844818487.mp4.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.asset(
      'assets/video/logoremover_1785844818487.mp4',
    );

    try {
      await _controller.initialize();
      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });

      _controller.setLooping(false);
      _controller.play();

      _controller.addListener(() {
        if (_controller.value.position >= _controller.value.duration && !_hasNavigated) {
          // Hold the final frame for 1000ms so the video splash doesn't feel rushed
          Future.delayed(const Duration(milliseconds: 1000), () {
            _navigateToNext();
          });
        }
      });

      // Backup safety timer in case video completion listener does not trigger
      final durationMs = _controller.value.duration.inMilliseconds;
      Future.delayed(Duration(milliseconds: durationMs + 1200), () {
        if (!_hasNavigated) {
          _navigateToNext();
        }
      });
    } catch (_) {
      // Fallback if video fails to initialize
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 2500), () {
          _navigateToNext();
        });
      }
    }
  }

  Future<void> _navigateToNext() async {
    if (_hasNavigated) return;
    _hasNavigated = true;

    try {
      final user = await ref.read(authStateProvider.future);
      if (!mounted) return;

      if (user != null && user.isProfileComplete) {
        context.go(RouteNames.home);
      } else {
        context.go(RouteNames.login);
      }
    } catch (_) {
      if (mounted) {
        context.go(RouteNames.login);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isInitialized && _controller.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            )
          else
            Container(
              color: colors.surface,
              child: Center(
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 180,
                  height: 180,
                ),
              ),
            ),
        ],
      ),
    );
  }
}


