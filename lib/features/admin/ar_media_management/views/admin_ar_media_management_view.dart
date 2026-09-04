import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/models/product/product_experience_type.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/widgets/states/app_empty_state.dart';
import '../../views/admin_shell.dart';
import '../viewmodels/admin_ar_model_preview_viewmodel.dart';
import '../viewmodels/ar_media_management_viewmodel.dart';
import '../widgets/admin_media_product_selector.dart';
import '../widgets/admin_room_ar_model_card.dart';
import '../widgets/admin_vto_configuration_card.dart';

class AdminArMediaManagementView extends StatelessWidget {
  const AdminArMediaManagementView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ArMediaManagementViewModel>();
    return PopScope(
      canPop: !viewModel.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _requestExit(context, viewModel);
      },
      child: viewModel.isProductScoped
          ? _buildProductScoped(context, viewModel)
          : _buildGeneral(context, viewModel),
    );
  }

  Widget _buildGeneral(
    BuildContext context,
    ArMediaManagementViewModel viewModel,
  ) {
    return AdminShell(
      currentIndex: 1,
      title: 'AR & Media',
      showGreeting: false,
      onBack: () => _requestExit(context, viewModel),
      child: _buildBody(context, viewModel, showSelector: true),
    );
  }

  Widget _buildProductScoped(
    BuildContext context,
    ArMediaManagementViewModel viewModel,
  ) {
    final title = viewModel.isRoomAr
        ? 'Configure Room AR'
        : 'Configure Virtual Try-On';
    return Scaffold(
      key: const Key('product_scoped_ar_media_scaffold'),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          key: const Key('product_scoped_back_button'),
          onPressed: () => _requestExit(context, viewModel),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title, style: AppTypography.title),
      ),
      body: SafeArea(
        child: _buildBody(context, viewModel, showSelector: false),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ArMediaManagementViewModel viewModel, {
    required bool showSelector,
  }) {
    final product = viewModel.selectedProduct;
    if (product == null) {
      return const AppEmptyState(
        title: 'No AR-enabled products yet',
        message: 'Choose Room AR or Virtual Try-On in Add/Edit Product first.',
        icon: Icons.view_in_ar_outlined,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSelector) ...[
            Text('AR & Media Asset Management', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Configure mock media for products with an AR experience.',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.m),
            AdminMediaProductSelector(
              selectedProduct: product,
              onTap: () => _showProductSelector(context, viewModel),
            ),
          ] else ...[
            Text(product.title, style: AppTypography.bodyLarge),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${product.sku} • ${product.experienceType.displayName}',
              style: AppTypography.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.m),
          if (viewModel.isRoomAr)
            AdminRoomArModelCard(
              viewModel: viewModel,
              onPreview: () => _openPreview(context, viewModel),
            )
          else if (viewModel.isVirtualTryOn)
            AdminVtoConfigurationCard(
              key: const Key('vto_configuration_card'),
              product: product,
              viewModel: viewModel,
              onChooseAsset: () =>
                  _showAssetSelector(context, viewModel, isReplacement: false),
              onReplace: () =>
                  _showAssetSelector(context, viewModel, isReplacement: true),
              onRemove: () => _confirmRemove(context, viewModel),
              onTest: () => AppToast.info(
                context,
                'Virtual Try-On testing will be available after VTO integration.',
              ),
            ),
          const SizedBox(height: AppSpacing.l),
          ElevatedButton.icon(
            key: Key(
              viewModel.isProductScoped
                  ? 'save_configuration_button'
                  : 'save_changes_button',
            ),
            onPressed: () => _save(context, viewModel),
            icon: const Icon(Icons.save_outlined),
            label: Text(
              viewModel.isProductScoped ? 'Save Configuration' : 'Save Changes',
            ),
          ),
          const SizedBox(height: AppSpacing.m),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    ArMediaManagementViewModel viewModel,
  ) async {
    final configured = viewModel.isRoomAr
        ? (viewModel.isRoomArConfigured || viewModel.hasUnsavedChanges)
        : viewModel.isVtoConfigured;
    if (!configured) {
      AppToast.error(context, 'Select an asset before saving configuration.');
      return;
    }
    if (viewModel.isRoomAr && viewModel.modelValidationError != null) {
      AppToast.error(context, viewModel.modelValidationError!);
      return;
    }
    if (viewModel.isProductScoped) {
      final result = viewModel.saveConfiguration();
      Navigator.of(context).pop(result);
      return;
    }
    final saved = await viewModel.saveChanges();
    if (!context.mounted) return;
    if (saved) {
      // A save can succeed (metadata written) yet leave a Storage-side note —
      // e.g. an explicit delete whose file could not be removed. Surface it
      // honestly instead of a bare "saved".
      final note = viewModel.modelWorkflowNote;
      if (note != null) {
        AppToast.warning(context, note);
      } else {
        AppToast.success(context, 'AR & Media changes saved');
      }
    } else {
      AppToast.error(
        context,
        viewModel.modelValidationError ??
            viewModel.modelWorkflowNote ??
            'Could not save AR & Media changes. Please try again.',
      );
    }
  }

  Future<void> _requestExit(
    BuildContext context,
    ArMediaManagementViewModel viewModel,
  ) async {
    if (viewModel.hasUnsavedChanges) {
      final discard = await _showDiscardDialog(context);
      if (discard != true || !context.mounted) return;
      viewModel.discardChanges();
    }
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else if (!viewModel.isProductScoped) {
      navigator.pushReplacementNamed(RouteNames.adminProducts);
    }
  }

  Future<bool?> _showDiscardDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.largeBorder,
          side: const BorderSide(color: AppColors.primary),
        ),
        title: const Text('Discard Changes?'),
        content: const Text('Your unsaved configuration changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  Future<void> _showProductSelector(
    BuildContext context,
    ArMediaManagementViewModel viewModel,
  ) async {
    if (viewModel.hasUnsavedChanges) {
      AppToast.info(
        context,
        'Save or discard changes before switching products.',
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.m,
                  AppSpacing.m,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select AR-enabled Product',
                        style: AppTypography.title,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: viewModel.eligibleProducts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final option = viewModel.eligibleProducts[index];
                    return AdminMediaProductOption(
                      product: option,
                      isSelected: option.id == viewModel.selectedProductId,
                      onTap: () {
                        viewModel.selectProduct(option.id);
                        Navigator.pop(sheetContext);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Open the admin 3D preview for the staged candidate (local file) or the
  /// committed model. Room AR only.
  void _openPreview(
    BuildContext context,
    ArMediaManagementViewModel viewModel,
  ) {
    final spec = viewModel.previewSpec;
    if (spec == null) {
      AppToast.info(context, 'Select or keep a model to preview it.');
      return;
    }
    Navigator.of(context).pushNamed(
      RouteNames.adminArModelPreview,
      arguments: AdminArModelPreviewArgs(
        localFilePath: spec.localFilePath,
        metadata: spec.metadata,
        productTitle: spec.title,
        widthM: spec.w,
        depthM: spec.d,
        heightM: spec.h,
      ),
    );
  }

  /// VTO-only mock asset selector (Room AR moved to real GLB upload in R16).
  Future<void> _showAssetSelector(
    BuildContext context,
    ArMediaManagementViewModel viewModel, {
    required bool isReplacement,
  }) async {
    const options = ArMediaManagementViewModel.vtoAssetOptions;
    final selected = await showModalBottomSheet<MockMediaAsset>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Choose Mock Garment Asset', style: AppTypography.title),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Frontend metadata only. No device file or binary is selected.',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: AppSpacing.s),
              ...options.map(
                (asset) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.mediumBorder,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                    leading: const Icon(
                      Icons.checkroom_outlined,
                      color: AppColors.primaryDark,
                    ),
                    title: Text(asset.fileName),
                    subtitle: Text(asset.fileSize),
                    trailing: const Icon(
                      Icons.add_circle_outline,
                      color: AppColors.primary,
                    ),
                    onTap: () => Navigator.pop(sheetContext, asset),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    viewModel.selectVtoAsset(selected);
    AppToast.success(
      context,
      isReplacement ? 'Replacement selected' : 'Asset selected',
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    ArMediaManagementViewModel viewModel,
  ) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.largeBorder,
          side: const BorderSide(color: AppColors.primary),
        ),
        title: const Text('Remove Asset?'),
        content: const Text(
          'Remove the Virtual Try-On garment asset from this configuration?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Remove',
              style: AppTypography.label.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (shouldRemove != true || !context.mounted) return;
    viewModel.removeVtoAsset();
    AppToast.success(context, 'Asset removed from configuration');
  }
}
