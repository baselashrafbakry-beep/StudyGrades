import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RecordingButton extends StatefulWidget {
  final bool isRecording;
  final bool isPaused;
  final bool isProcessing;
  final VoidCallback onPressed;
  final double size;

  const RecordingButton({
    super.key,
    required this.isRecording,
    required this.isPaused,
    required this.isProcessing,
    required this.onPressed,
    this.size = 110,
  });

  @override
  State<RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<RecordingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isRecording && !widget.isPaused;

    return GestureDetector(
      onTap: widget.isProcessing ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final pulse = active ? 1.0 + (_ctrl.value * 0.18) : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (active)
                Container(
                  width: widget.size * 1.5,
                  height: widget.size * 1.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.recordingActive.withValues(
                      alpha: 0.15 * (1 - _ctrl.value),
                    ),
                  ),
                ),
              if (active)
                Container(
                  width: widget.size * 1.25,
                  height: widget.size * 1.25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.recordingActive.withValues(
                      alpha: 0.25 * (1 - _ctrl.value),
                    ),
                  ),
                ),
              Transform.scale(
                scale: pulse,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    gradient: widget.isRecording
                        ? (widget.isPaused
                            ? const LinearGradient(
                                colors: [Color(0xFFFFB74D), Color(0xFFFB8C00)],
                              )
                            : AppColors.recordGradient)
                        : AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (widget.isRecording
                                ? AppColors.recordingActive
                                : AppColors.primary)
                            .withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: widget.isProcessing
                      ? const Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          ),
                        )
                      : Icon(
                          widget.isRecording
                              ? (widget.isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.stop_rounded)
                              : Icons.mic_rounded,
                          color: Colors.white,
                          size: widget.size * 0.45,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
