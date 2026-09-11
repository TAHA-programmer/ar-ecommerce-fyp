import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/models/product/product_vto_model_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../app/routes/route_names.dart';
import '../models/virtual_try_on_session_args.dart';
import '../viewmodels/virtual_try_on_setup_viewmodel.dart';
import '../widgets/vto_product_summary_card.dart';
import '../widgets/vto_positioning_section.dart';
import '../widgets/vto_consent_card.dart';
import '../widgets/vto_compatibility_card.dart';

/// Virtual Try-On setup/consent screen (Phase 9.3 Stage 5) — product +
/// variant selection, accurate "how it works" / positioning / consent /
/// compatibility guidance, and the gate into the capture/generate/result
/// screen ([RouteNames.virtualTryOnSession]).
class VirtualTryOnSetupView extends StatelessWidget {
  const VirtualTryOnSetupView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Image.asset(AppAssets.headerLogo, height: 28),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Consumer<VirtualTryOnSetupViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (viewModel.error != null || viewModel.product == null) {
              return _ErrorState(
                message: viewModel.error ?? 'Product not found.',
              );
            }

            final product = viewModel.product!;
            final isFemaleModel =
                product.vtoModelType == ProductVtoModelType.female;

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        VtoProductSummaryCard(
                          product: product,
                          selectedColor: viewModel.selectedColor,
                          selectedSize: viewModel.selectedSize,
                          colorHasPreview: (c) =>
                              viewModel.colorHasPreview(product, c),
                          onColorSelected: viewModel.selectColor,
                          onSizeSelected: viewModel.selectSize,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: AppColors.primaryDark,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'How Virtual Try-On Works',
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Take or choose a photo of yourself. We use Google's "
                          "Gemini AI to generate a visual preview of you "
                          "wearing this item in your selected colour. It's an "
                          "appearance estimate, not a fit or sizing guarantee "
                          "— actual drape, texture and size will vary.",
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: 24),
                        VtoPositioningSection(isFemaleModel: isFemaleModel),
                        const SizedBox(height: 24),
                        VtoConsentCard(
                          checked: viewModel.consentChecked,
                          onChanged: viewModel.setConsentChecked,
                        ),
                        const SizedBox(height: 16),
                        const VtoCompatibilityCard(),
                        const SizedBox(height: 32),
                        _buildPrimaryButton(context, viewModel),
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

  Widget _buildPrimaryButton(
    BuildContext context,
    VirtualTryOnSetupViewModel viewModel,
  ) {
    return ElevatedButton(
      onPressed: viewModel.canStart
          ? () => _startTryOn(context, viewModel)
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        disabledBackgroundColor: AppColors.neutralLight,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.checkroom),
          SizedBox(width: 8),
          Text(
            'Start Try-On',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _startTryOn(BuildContext context, VirtualTryOnSetupViewModel viewModel) {
    final authState = context.read<AuthSessionState>();
    if (!authState.isAuthenticated) {
      _requireSignInThen(context, () => _startTryOn(context, viewModel));
      return;
    }

    final args = VirtualTryOnSessionArgs(
      productId: viewModel.productId,
      colorKey: viewModel.selectedColor!.name,
      size: viewModel.selectedSize?.name,
      idempotencyKey: viewModel.startNewAttemptIdempotencyKey(),
    );
    Navigator.pushNamed(
      context,
      RouteNames.virtualTryOnSession,
      arguments: args,
    );
  }

  Widget _buildSecondaryButton(BuildContext context) {
    return OutlinedButton(
      onPressed: () {
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
          Icon(Icons.swap_horiz),
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

/// Routes a signed-out customer to login, then resumes [onSignedIn] once
/// they return. `LoginView` pops with `true` on success when it was reached
/// via a push (rather than replacing to Home) — see its doc comment.
Future<void> _requireSignInThen(
  BuildContext context,
  VoidCallback onSignedIn,
) async {
  final result = await Navigator.pushNamed(context, RouteNames.login);
  if (result == true && context.mounted) {
    onSignedIn();
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.checkroom_outlined,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
