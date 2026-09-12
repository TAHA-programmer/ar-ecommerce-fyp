import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../app/routes/route_names.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../../product_details/widgets/product_size_selector.dart';
import '../models/virtual_try_on_session_phase.dart';
import '../services/virtual_try_on_exception.dart';
import '../viewmodels/virtual_try_on_session_viewmodel.dart';

/// Virtual Try-On capture → upload → generate → result screen (Phase 9.3
/// Stage 5). See [VirtualTryOnSessionPhase] for the state machine this
/// renders.
class VirtualTryOnSessionView extends StatefulWidget {
  const VirtualTryOnSessionView({super.key});

  @override
  State<VirtualTryOnSessionView> createState() =>
      _VirtualTryOnSessionViewState();
}

class _VirtualTryOnSessionViewState extends State<VirtualTryOnSessionView> {
  PermissionStatus? _cameraPermission;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final s = await Permission.camera.status;
    if (mounted) setState(() => _cameraPermission = s);
  }

  Future<void> _handleTakePhoto() async {
    var status = _cameraPermission ?? await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (mounted) setState(() => _cameraPermission = status);
    }
    if (!mounted) return;
    if (status.isGranted) {
      context.read<VirtualTryOnSessionViewModel>().captureFromCamera();
    } else if (status.isPermanentlyDenied || status.isRestricted) {
      _showSettingsDialog();
    } else {
      AppToast.warning(
        context,
        'Camera permission is needed to take a photo. You can choose from '
        'gallery instead.',
      );
    }
  }

  void _showSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Camera access needed'),
        content: const Text(
          'Enable camera access in Settings to take a photo, or choose one '
          'from your gallery instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmLeaveWhileGenerating() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave while generating?'),
        content: const Text(
          "Your preview will still finish generating. You can come back "
          "later, but it won't be shown here if you leave now.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleBack(VirtualTryOnSessionViewModel vm) async {
    switch (vm.phase) {
      case VirtualTryOnSessionPhase.capturePrompt:
      case VirtualTryOnSessionPhase.photoPreview:
      case VirtualTryOnSessionPhase.failed:
        if (mounted) Navigator.pop(context);
        return;
      case VirtualTryOnSessionPhase.uploading:
        await vm.cancelDuringUpload();
        return;
      case VirtualTryOnSessionPhase.generating:
        final leave = await _confirmLeaveWhileGenerating();
        if (leave && mounted) Navigator.pop(context);
        return;
      case VirtualTryOnSessionPhase.success:
        await vm.deleteResultOnLeave();
        if (mounted) Navigator.pop(context);
        return;
    }
  }

  Future<void> _requireSignInThenRetry(VirtualTryOnSessionViewModel vm) async {
    final result = await Navigator.pushNamed(context, RouteNames.login);
    if (result == true && mounted) {
      vm.retryAfterFailure();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context.read<VirtualTryOnSessionViewModel>());
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          title: const Text('Virtual Try-On'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                _handleBack(context.read<VirtualTryOnSessionViewModel>()),
          ),
        ),
        body: SafeArea(
          child: Consumer<VirtualTryOnSessionViewModel>(
            builder: (context, vm, _) {
              if (vm.isLoadingProduct) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              if (vm.loadError != null || vm.product == null) {
                return _MessageState(
                  icon: Icons.error_outline,
                  message: vm.loadError ?? 'Product not found.',
                  actionLabel: 'Go Back',
                  onAction: () => Navigator.pop(context),
                );
              }

              switch (vm.phase) {
                case VirtualTryOnSessionPhase.capturePrompt:
                  return _CapturePrompt(
                    onTakePhoto: _handleTakePhoto,
                    onPickGallery: () => vm.pickFromGallery(),
                    isBusy: vm.isBusy,
                    rejectionMessage: vm.photoRejectionMessage,
                  );
                case VirtualTryOnSessionPhase.photoPreview:
                  return _PhotoPreview(
                    photoBytes: vm.previewBytes!,
                    onUsePhoto: vm.usePhotoAndGenerate,
                    onRetake: vm.discardPickedPhoto,
                  );
                case VirtualTryOnSessionPhase.uploading:
                  return _ProgressState(
                    title: 'Preparing your photo…',
                    subtitle: 'Uploading securely.',
                    onCancel: vm.cancelDuringUpload,
                  );
                case VirtualTryOnSessionPhase.generating:
                  return const _GeneratingProgress();
                case VirtualTryOnSessionPhase.success:
                  return _ResultView(vm: vm);
                case VirtualTryOnSessionPhase.failed:
                  return _FailedState(
                    vm: vm,
                    onRequireSignIn: () => _requireSignInThenRetry(vm),
                  );
              }
            },
          ),
        ),
      ),
    );
  }
}

class _CapturePrompt extends StatelessWidget {
  final VoidCallback onTakePhoto;
  final VoidCallback onPickGallery;
  final bool isBusy;
  final String? rejectionMessage;

  const _CapturePrompt({
    required this.onTakePhoto,
    required this.onPickGallery,
    required this.isBusy,
    required this.rejectionMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.accessibility_new,
            size: 56,
            color: AppColors.primaryDark,
          ),
          const SizedBox(height: 16),
          Text(
            'Take or choose a photo',
            style: AppTypography.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (rejectionMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                rejectionMessage!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _GuidanceLine(text: 'Full body or head-to-hip, facing forward'),
                _GuidanceLine(text: 'Plain, uncluttered background'),
                _GuidanceLine(text: 'Even, front-facing lighting'),
                _GuidanceLine(text: 'Arms slightly away from your sides'),
                _GuidanceLine(text: 'One person only in the photo'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: isBusy ? null : onTakePhoto,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Take Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isBusy ? null : onPickGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose from Gallery'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (isBusy) ...[
            const SizedBox(height: 16),
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuidanceLine extends StatelessWidget {
  final String text;
  const _GuidanceLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTypography.bodySmall)),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final Uint8List photoBytes;
  final VoidCallback onUsePhoto;
  final VoidCallback onRetake;

  const _PhotoPreview({
    required this.photoBytes,
    required this.onUsePhoto,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                photoBytes,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: onUsePhoto,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text('Use This Photo'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetake,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Retake / Choose Different Photo'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onCancel;

  const _ProgressState({
    required this.title,
    required this.subtitle,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (onCancel != null) ...[
              const SizedBox(height: 24),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ],
        ),
      ),
    );
  }
}

class _GeneratingProgress extends StatefulWidget {
  const _GeneratingProgress();

  @override
  State<_GeneratingProgress> createState() => _GeneratingProgressState();
}

class _GeneratingProgressState extends State<_GeneratingProgress> {
  Timer? _timer;
  bool _showLongerNotice = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _showLongerNotice = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ProgressState(
      title: 'Generating your preview',
      subtitle: _showLongerNotice
          ? 'Still working. Some items take a little longer to generate, '
                "so please wait. You can leave this screen once it's done."
          : 'This can take up to a minute. Please wait.',
    );
  }
}

class _ResultView extends StatelessWidget {
  final VirtualTryOnSessionViewModel vm;
  const _ResultView({required this.vm});

  @override
  Widget build(BuildContext context) {
    final product = vm.product!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              vm.resultBytes!,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "This is a generated preview, not an actual photo. It's a "
            'visual estimate only, not a guarantee of exact fit, sizing, '
            'or fabric drape.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (vm.eligibleColors.length > 1) ...[
            Text(
              'Try another colour',
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: vm.eligibleColors.map((c) {
                final isSelected = c.name == vm.currentColorKey;
                return ChoiceChip(
                  label: Text(_colorLabel(c)),
                  selected: isSelected,
                  onSelected: (_) => vm.changeColor(c.name),
                  // Solid, matching "Add to Cart"'s background — the prior
                  // 15%-alpha tint left the (white) label/checkmark almost
                  // unreadable against it. `labelStyle: null` for the
                  // unselected case falls back to the ambient chip theme
                  // default, so unselected chips (e.g. Sky Blue) are
                  // pixel-identical to before.
                  selectedColor: AppColors.primary,
                  checkmarkColor: AppColors.white,
                  labelStyle: isSelected
                      ? const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (product.availableSizes.isNotEmpty) ...[
            ProductSizeSelector(
              availableSizes: product.availableSizes,
              selectedSize: _sizeFor(vm.currentSize),
              onSizeSelected: (s) => vm.changeSize(s.name),
            ),
            if (vm.sizeOnlyChangedNotice) ...[
              const SizedBox(height: 8),
              Text(
                'Size affects your order, not this preview. Check the size '
                'chart for fit.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
          ElevatedButton.icon(
            onPressed: () => _addToCart(context),
            icon: const Icon(Icons.shopping_cart_outlined),
            label: const Text('Add to Cart'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: vm.startRetake,
            icon: const Icon(Icons.replay),
            label: const Text('Retake Photo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _deletePreview(context),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete This Preview'),
          ),
        ],
      ),
    );
  }

  ProductSize? _sizeFor(String? name) {
    if (name == null) return null;
    for (final s in ProductSize.values) {
      if (s.name == name) return s;
    }
    return null;
  }

  String _colorLabel(ProductColorOption c) {
    switch (c) {
      case ProductColorOption.beige:
        return 'Beige';
      case ProductColorOption.gray:
        return 'Gray';
      case ProductColorOption.black:
        return 'Black';
      case ProductColorOption.brown:
        return 'Brown';
      case ProductColorOption.blue:
        return 'Sky Blue';
      case ProductColorOption.green:
        return 'Green';
      case ProductColorOption.pink:
        return 'Pink';
    }
  }

  Future<void> _addToCart(BuildContext context) async {
    final error = await vm.addSelectedVariantToCart();
    if (!context.mounted) return;
    if (error != null) {
      AppToast.error(context, error);
    } else {
      AppToast.success(context, 'Added to Cart');
    }
  }

  Future<void> _deletePreview(BuildContext context) async {
    await vm.deletePreviewAndReset();
    if (context.mounted) {
      AppToast.info(context, 'Preview deleted.');
    }
  }
}

class _FailedState extends StatelessWidget {
  final VirtualTryOnSessionViewModel vm;
  final VoidCallback onRequireSignIn;

  const _FailedState({required this.vm, required this.onRequireSignIn});

  @override
  Widget build(BuildContext context) {
    final error = vm.lastError;
    final isNotSignedIn = error?.kind == VirtualTryOnErrorKind.notSignedIn;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              error?.message ??
                  'Something went wrong generating your preview. Please try again.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge,
            ),
            const SizedBox(height: 24),
            if (isNotSignedIn)
              ElevatedButton(
                onPressed: onRequireSignIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                ),
                child: const Text('Sign In'),
              )
            else
              ElevatedButton(
                onPressed: vm.retryAfterFailure,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                ),
                child: const Text('Retry'),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _MessageState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
