import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../app/routes/route_names.dart';
import '../viewmodels/room_ar_preparation_viewmodel.dart';
import '../widgets/room_ar_product_card.dart';
import '../widgets/room_ar_instruction_item.dart';
import '../widgets/room_ar_info_card.dart';
import '../widgets/room_ar_warning_card.dart';

/// Room-AR preparation screen (Phase 9.2 R15/R17 + R7/R8).
///
/// Always in the flow between Product Details ("View in Your Room") and the
/// launched Room-AR experience. It adapts to the tier the device can actually
/// run — Tier-2 Marker AR (print + place a marker, camera) or the Tier-3
/// Interactive 3D Preview (no camera) — and launches only that one product.
/// Ineligible products load the screen but cannot launch anything.
class RoomArPreparationView extends StatelessWidget {
  final String productId;

  const RoomArPreparationView({super.key, required this.productId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Consumer<RoomArPreparationViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (viewModel.error != null) {
              return _buildErrorState(context, viewModel.error!);
            }
            final product = viewModel.product;
            if (product == null) {
              return _buildErrorState(context, 'Product not found.');
            }

            return Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 16.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RoomArProductCard(product: product),
                        const SizedBox(height: 32),
                        Text(
                          'View in Your Room',
                          style: AppTypography.headingLarge.copyWith(
                            fontFamily: 'Playfair Display',
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._buildBody(context, viewModel),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              viewModel.canStartAr || viewModel.canPreview
                                  ? 'Cancel'
                                  : 'Go Back',
                              style: AppTypography.label.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, RoomArPreparationViewModel vm) {
    if (vm.canStartAr) return _tier2Body(context, vm);
    if (vm.canPreview) return _tier3Body(context, vm);

    // Eligible product, but the device can run neither tier, OR the product has
    // no approved model yet.
    final msg = vm.deviceUnsupported
        ? 'This device can\'t run the 3D experience for this product. You can '
              'still browse its photos and details.'
        : 'A 3D model for this product isn\'t ready yet, so Room AR can\'t be '
              'started for it. You can still browse its photos and details.';
    return [
      Text(
        msg,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textPrimary,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 24),
      const RoomArWarningCard(),
    ];
  }

  // ── Tier 2 — Marker AR ─────────────────────────────────────────────────────
  List<Widget> _tier2Body(BuildContext context, RoomArPreparationViewModel vm) {
    return [
      Text(
        'Room AR anchors this piece to a printed marker on your floor, so you '
        'can walk around it at its real size before you buy.',
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textPrimary,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 24),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(
            child: RoomArInstructionItem(
              stepNumber: 1,
              icon: Icons.print_outlined,
              text: 'Print the\nmarker at\n100% size',
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: RoomArInstructionItem(
              stepNumber: 2,
              icon: Icons.crop_free,
              text: 'Lay it flat\non the floor,\nfully in view',
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: RoomArInstructionItem(
              stepNumber: 3,
              icon: Icons.wb_sunny_outlined,
              text: 'Use a\nwell-lit\nroom',
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: RoomArInstructionItem(
              stepNumber: 4,
              icon: Icons.screen_rotation_outlined,
              text: 'Move the\nphone slowly,\nkeep distance',
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      _buildInArGuide(),
      const SizedBox(height: 16),
      const RoomArInfoCard(),
      const SizedBox(height: 16),
      const RoomArWarningCard(),
      const SizedBox(height: 32),
      _primaryButton(
        label: 'Start AR',
        icon: Icons.view_in_ar_outlined,
        onPressed: () => Navigator.pushNamed(
          context,
          RouteNames.roomArSession,
          arguments: vm.sessionArgs,
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: () => Navigator.pushNamed(
            context,
            RouteNames.roomArPreview,
            arguments: vm.sessionArgs,
          ),
          child: Text(
            'No printer? View a 3D preview instead',
            style: AppTypography.label.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ];
  }

  // ── Tier 3 — Interactive 3D Preview ────────────────────────────────────────
  List<Widget> _tier3Body(BuildContext context, RoomArPreparationViewModel vm) {
    return [
      Text(
        'Camera AR isn\'t available on this device, so you\'ll see an '
        'interactive 3D preview instead — rotate, pan and zoom the piece and '
        'see it at its real dimensions. No camera or marker needed.',
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textPrimary,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 24),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(
            child: RoomArInstructionItem(
              stepNumber: 1,
              icon: Icons.threed_rotation,
              text: 'Drag to\nrotate the\npiece',
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: RoomArInstructionItem(
              stepNumber: 2,
              icon: Icons.pinch,
              text: 'Pinch to\nzoom · two\nfingers to pan',
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: RoomArInstructionItem(
              stepNumber: 3,
              icon: Icons.restart_alt,
              text: 'Double-tap\nto reset\nthe view',
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const RoomArInfoCard(),
      const SizedBox(height: 32),
      _primaryButton(
        label: 'View 3D Preview',
        icon: Icons.threed_rotation,
        onPressed: () => Navigator.pushNamed(
          context,
          RouteNames.roomArPreview,
          arguments: vm.sessionArgs,
        ),
      ),
    ];
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: AppTypography.label.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildInArGuide() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutralMediumLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Once the marker is tracked',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _guideRow(
            Icons.straighten,
            'Tap the ruler to match the marker\'s real printed size — this '
            'calibrates the scale.',
          ),
          _guideRow(
            Icons.touch_app_outlined,
            'Tap the floor near the marker to place the piece; drag to move it '
            '(it stays within 0.6 m of the marker).',
          ),
          _guideRow(
            Icons.rotate_right,
            'Twist with two fingers or use the slider to rotate. "Face me" turns '
            'it toward you; "Reset" recentres it.',
          ),
        ],
      ),
    );
  }

  Widget _guideRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.textPrimary,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Image.asset(AppAssets.headerLogo, height: 32),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
