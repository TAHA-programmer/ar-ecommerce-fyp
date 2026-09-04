import 'package:flutter/material.dart';

import '../../../../core/models/product/product_color_option.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/models/product/product_size.dart';
import '../../../../core/models/product/product_vto_model_type.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/product_image_view.dart';
import '../viewmodels/ar_media_management_viewmodel.dart';
import 'admin_media_components.dart';

class AdminVtoConfigurationCard extends StatelessWidget {
  final ProductModel product;
  final ArMediaManagementViewModel viewModel;
  final VoidCallback onChooseAsset;
  final VoidCallback onReplace;
  final VoidCallback onRemove;
  final VoidCallback onTest;

  const AdminVtoConfigurationCard({
    super.key,
    required this.product,
    required this.viewModel,
    required this.onChooseAsset,
    required this.onReplace,
    required this.onRemove,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final configured = viewModel.isVtoConfigured;
    return AdminMediaCard(
      icon: Icons.checkroom_outlined,
      title: 'Virtual Try-On (Garment Asset)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Upload Garment Asset', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Supported mock formats: GLTF (.glb, .gltf), USDZ (.usdz), FBX (.fbx)',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          AdminMediaUploadTile(
            fileName: viewModel.vtoAssetFileName,
            fileSize: viewModel.vtoAssetFileSize,
            emptyLabel: 'Choose mock garment asset',
            onTap: onChooseAsset,
          ),
          if (configured) ...[
            const SizedBox(height: AppSpacing.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Upload Progress', style: AppTypography.bodySmall),
                Text('100%', style: AppTypography.bodySmall),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            const LinearProgressIndicator(value: 1),
          ],
          const SizedBox(height: AppSpacing.m),
          _dropdown<String>(
            label: 'Garment Type',
            value: viewModel.garmentType,
            items: const ['Top', 'Jacket', 'Hoodie', 'Dress', 'Bottom'],
            labelFor: (value) => value,
            onChanged: viewModel.setGarmentType,
          ),
          const SizedBox(height: AppSpacing.s),
          _dropdown<ProductVtoModelType>(
            label: 'Model Type',
            value: product.vtoModelType,
            items: ProductVtoModelType.values,
            labelFor: (value) => value.displayName,
            hint: 'Select Model Type',
            onChanged: viewModel.setVtoModelType,
          ),
          const SizedBox(height: AppSpacing.s),
          Text('Body Area', style: AppTypography.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: MockBodyArea.values
                .map(
                  (area) => ChoiceChip(
                    label: Text(area.label),
                    selected: viewModel.bodyArea == area,
                    selectedColor: AppColors.primary,
                    onSelected: (_) => viewModel.setBodyArea(area),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.s),
          _dropdown<ProductColorOption>(
            label: 'Associate Asset with Color',
            value: viewModel.associatedColor,
            items: product.availableColors.toList(),
            labelFor: (value) => _capitalized(value.name),
            hint: product.availableColors.isEmpty
                ? 'No colors configured'
                : null,
            onChanged: viewModel.setAssociatedColor,
          ),
          const SizedBox(height: AppSpacing.s),
          _dropdown<ProductSize>(
            label: 'Associate Asset with Size',
            value: viewModel.associatedSize,
            items: product.availableSizes.toList(),
            labelFor: (value) => value.label,
            hint: product.availableSizes.isEmpty ? 'No sizes configured' : null,
            onChanged: viewModel.setAssociatedSize,
          ),
          const SizedBox(height: AppSpacing.m),
          Text('Alignment Preview', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          AdminMediaPreview(
            label: configured ? 'Alignment preview' : 'No garment selected',
            child: ProductImageView(
              imageRef: product.mainImage,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Text('Validation Status', style: AppTypography.label),
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: AdminMediaStatus(configured: configured)),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          AdminMediaActionRow(
            testLabel: 'Test Try-On',
            onTest: onTest,
            onReplace: configured ? onReplace : null,
            onRemove: configured ? onRemove : null,
          ),
          const SizedBox(height: AppSpacing.s),
          AdminMediaConfigurationStatus(
            label: 'Virtual Try-On Status',
            configured: configured,
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) labelFor,
    required ValueChanged<T> onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodySmall),
        const SizedBox(height: AppSpacing.xxs),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          hint: hint == null ? null : Text(hint),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelFor(item)),
                ),
              )
              .toList(),
          onChanged: items.isEmpty
              ? null
              : (newValue) {
                  if (newValue != null) onChanged(newValue);
                },
          style: AppTypography.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: AppRadii.mediumBorder),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.mediumBorder,
              borderSide: const BorderSide(color: AppColors.neutralMediumLight),
            ),
          ),
        ),
      ],
    );
  }

  String _capitalized(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
