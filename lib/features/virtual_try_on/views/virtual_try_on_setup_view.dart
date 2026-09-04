import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/models/product/product_vto_model_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../../../app/routes/route_names.dart';
import '../viewmodels/virtual_try_on_setup_viewmodel.dart';
import '../widgets/vto_camera_option_card.dart';
import '../models/virtual_try_on_camera_type.dart';
import '../widgets/vto_product_summary_card.dart';
import '../widgets/vto_positioning_section.dart';
import '../widgets/vto_privacy_card.dart';
import '../widgets/vto_compatibility_card.dart';

class VirtualTryOnSetupView extends StatelessWidget {
  const VirtualTryOnSetupView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Consumer<VirtualTryOnSetupViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (viewModel.error != null || viewModel.product == null) {
              return Center(
                child: Text(
                  viewModel.error ?? 'Failed to load product',
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.error,
                  ),
                ),
              );
            }

            final product = viewModel.product!;
            final isFemale = product.vtoModelType == ProductVtoModelType.female;

            return Column(
              children: [
                _buildHeader(context, isFemale),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        VtoProductSummaryCard(product: product),
                        const SizedBox(height: 24),
                        if (isFemale) ...[
                          Text('Virtual Try-On', style: AppTypography.title),
                          const SizedBox(height: 8),
                          Text(
                            'Our virtual try-on uses AR to show how this item fits and looks on you in real time.',
                            style: AppTypography.bodySmall,
                          ),
                        ] else ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: AppColors.primaryDark,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'How Virtual Try-On works',
                                style: AppTypography.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We use advanced body mapping and AI to show how the selected item fits and looks on you in real time.',
                            style: AppTypography.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (isFemale)
                          Text(
                            'Choose your camera',
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          Row(
                            children: [
                              const Icon(Icons.camera_alt_outlined),
                              const SizedBox(width: 8),
                              Text(
                                'Choose Camera',
                                style: AppTypography.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: VtoCameraOptionCard(
                                type: VirtualTryOnCameraType.front,
                                isSelected:
                                    viewModel.selectedCamera ==
                                    VirtualTryOnCameraType.front,
                                onTap: () => viewModel.selectCamera(
                                  VirtualTryOnCameraType.front,
                                ),
                                isFemaleVariant: isFemale,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: VtoCameraOptionCard(
                                type: VirtualTryOnCameraType.rear,
                                isSelected:
                                    viewModel.selectedCamera ==
                                    VirtualTryOnCameraType.rear,
                                onTap: () => viewModel.selectCamera(
                                  VirtualTryOnCameraType.rear,
                                ),
                                isFemaleVariant: isFemale,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        VtoPositioningSection(isFemaleVariant: isFemale),
                        const SizedBox(height: 32),
                        VtoPrivacyCard(isFemaleVariant: isFemale),
                        const SizedBox(height: 16),
                        VtoCompatibilityCard(isFemaleVariant: isFemale),
                        const SizedBox(height: 32),
                        _buildPrimaryButton(context, isFemale),
                        const SizedBox(height: 16),
                        _buildSecondaryButton(context),
                        const SizedBox(height: 16),
                        _buildCancelButton(context),
                        const SizedBox(height: 24),
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

  Widget _buildHeader(BuildContext context, bool isFemale) {
    if (isFemale) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.neutralLight),
              ),
              child: IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: Center(
                child: Image.asset(AppAssets.headerLogo, height: 32),
              ),
            ),
            const SizedBox(width: 48), // Balance for back button
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            Expanded(
              child: Center(
                child: Column(
                  children: [
                    Image.asset(AppAssets.headerLogo, height: 24),
                    const SizedBox(height: 4),
                    Text('Virtual Try-On', style: AppTypography.title),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24), // Balance for back button
          ],
        ),
      );
    }
  }

  Widget _buildPrimaryButton(BuildContext context, bool isFemale) {
    return ElevatedButton(
      onPressed: () {
        AppToast.info(context, 'Coming soon');
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFemale ? Icons.view_in_ar : Icons.checkroom,
          ), // Approximation of icons
          const SizedBox(width: 8),
          const Text(
            'Start Try-On',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryButton(BuildContext context) {
    return OutlinedButton(
      onPressed: () {
        // Change product -> Return to catalog, preserving Home base.
        Navigator.pushNamedAndRemoveUntil(
          context,
          RouteNames.explore,
          ModalRoute.withName(RouteNames.home),
        );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_horiz), // Approximation of the change product icon
          SizedBox(width: 8),
          Text(
            'Change Product',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelButton(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
      child: const Text('Cancel', style: TextStyle(fontSize: 16)),
    );
  }
}
