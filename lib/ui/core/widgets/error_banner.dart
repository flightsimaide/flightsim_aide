import 'package:flutter/material.dart';

/// An error message with an icon (so it is not conveyed by colour alone) and
/// an optional dismiss button.
class ErrorBanner extends StatelessWidget {
  /// Creates an error banner.
  const ErrorBanner({required this.message, this.onDismiss, super.key});

  /// The text shown to the user.
  final String message;

  /// Called when the dismiss button is tapped; no button when null.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  color: scheme.onErrorContainer,
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
