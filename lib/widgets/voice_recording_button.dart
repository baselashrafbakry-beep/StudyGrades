import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class VoiceRecordingButton extends StatelessWidget {
  final bool isListening;
  final bool isProcessing;
  final VoidCallback onTap;
  final AnimationController pulseCtrl;

  const VoiceRecordingButton({
    super.key,
    required this.isListening,
    required this.isProcessing,
    required this.onTap,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return Column(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'جاري المعالجة...',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedBuilder(
            animation: pulseCtrl,
            builder: (ctx, child) {
              final scale = isListening ? (1 + 0.15 * pulseCtrl.value) : 1.0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (isListening) ...[
                    // Outer pulse rings
                    Transform.scale(
                      scale: 1 + 0.7 * pulseCtrl.value,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.recordingActive
                              .withValues(alpha: 0.15 * (1 - pulseCtrl.value)),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: 1 + 0.4 * pulseCtrl.value,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.recordingActive
                              .withValues(alpha: 0.25 * (1 - pulseCtrl.value)),
                        ),
                      ),
                    ),
                  ],
                  Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isListening
                            ? AppColors.recordGradient
                            : AppColors.primaryGradient,
                        boxShadow: [
                          BoxShadow(
                            color: (isListening
                                    ? AppColors.recordingActive
                                    : AppColors.primary)
                                .withValues(alpha: 0.4),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        isListening ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            isListening ? 'اضغط للإيقاف' : 'اضغط للبدء',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color:
                  isListening ? AppColors.recordingActive : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
