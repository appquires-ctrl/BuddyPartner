import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/network_connectivity_service.dart';
import 'package:buddypartner/core/widgets/feedback/no_internet_dialog.dart';

/// Global overlay that monitors network state and renders a sleek top status pill.
class GlobalNetworkStatusBar extends ConsumerStatefulWidget {
  final Widget child;

  const GlobalNetworkStatusBar({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<GlobalNetworkStatusBar> createState() => _GlobalNetworkStatusBarState();
}

class _GlobalNetworkStatusBarState extends ConsumerState<GlobalNetworkStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _offsetAnimation;
  bool _wasOffline = false;
  bool _showBackOnline = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(networkConnectivityProvider);

    // Track state transitions for the "Back Online" banner
    if (status == NetworkStatus.disconnected) {
      _wasOffline = true;
      _showBackOnline = false;
      _slideController.forward();
    } else if (status == NetworkStatus.connected && _wasOffline) {
      _wasOffline = false;
      _showBackOnline = true;
      _slideController.forward();
      // Auto-hide the "Back Online" banner after 2.5 seconds
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && ref.read(networkConnectivityProvider) == NetworkStatus.connected) {
          _slideController.reverse().then((_) {
            if (mounted) setState(() => _showBackOnline = false);
          });
        }
      });
    }

    return Stack(
      children: [
        widget.child,

        // Floating Animated Top Network Status Banner
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: SlideTransition(
              position: _offsetAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (status == NetworkStatus.disconnected) {
                          NoInternetDialog.show(context);
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _showBackOnline
                              ? const Color(0xFF10B981)
                              : const Color(0xFF1E1528),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _showBackOnline
                                ? const Color(0xFF34D399)
                                : const Color(0xFFEF4444).withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_showBackOnline
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444))
                                  .withValues(alpha: 0.3),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showBackOnline) ...[
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Connection Restored',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ] else ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'No Internet Connection',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Retry',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
