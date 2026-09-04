import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class AdminMediaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const AdminMediaCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.largeBorder,
        border: Border.all(color: AppColors.primary),
        boxShadow: AppShadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.minTouchTarget,
                height: AppSizes.minTouchTarget,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.18),
                  borderRadius: AppRadii.mediumBorder,
                ),
                child: Icon(icon, color: AppColors.primaryDark),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          child,
        ],
      ),
    );
  }
}

class AdminMediaUploadTile extends StatelessWidget {
  final String? fileName;
  final String fileSize;
  final String emptyLabel;
  final VoidCallback onTap;

  const AdminMediaUploadTile({
    super.key,
    required this.fileName,
    required this.fileSize,
    required this.emptyLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = fileName != null;
    return InkWell(
      key: const Key('admin_media_upload_tile'),
      onTap: onTap,
      borderRadius: AppRadii.mediumBorder,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.mediumBorder,
          border: Border.all(color: AppColors.neutralMediumLight),
        ),
        child: Row(
          children: [
            Icon(
              hasFile
                  ? Icons.inventory_2_outlined
                  : Icons.cloud_upload_outlined,
              color: AppColors.primaryDark,
              size: AppSizes.iconLarge,
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName ?? emptyLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hasFile) Text(fileSize, style: AppTypography.bodySmall),
                ],
              ),
            ),
            Icon(
              hasFile ? Icons.check_circle : Icons.add_circle_outline,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class AdminMediaStatus extends StatelessWidget {
  final bool configured;

  const AdminMediaStatus({super.key, required this.configured});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: configured
            ? AppColors.primaryLight.withValues(alpha: 0.16)
            : AppColors.neutralLight,
        borderRadius: AppRadii.pillBorder,
        border: Border.all(
          color: configured ? AppColors.primary : AppColors.neutralMedium,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            configured ? Icons.check_circle : Icons.info_outline,
            size: AppSizes.iconSmall,
            color: configured ? AppColors.primaryDark : AppColors.neutralDark,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              configured ? 'Validated' : 'No asset selected',
              style: AppTypography.caption.copyWith(
                color: configured
                    ? AppColors.primaryDark
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminMediaConfigurationStatus extends StatelessWidget {
  final String label;
  final bool configured;

  const AdminMediaConfigurationStatus({
    super.key,
    required this.label,
    required this.configured,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: configured
            ? AppColors.primaryLight.withValues(alpha: 0.12)
            : AppColors.neutralLight,
        borderRadius: AppRadii.mediumBorder,
        border: Border.all(
          color: configured ? AppColors.primary : AppColors.neutralMediumLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            configured ? Icons.check_circle : Icons.info_outline,
            color: configured ? AppColors.primaryDark : AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodySmall),
                Text(
                  configured ? 'Configured' : 'Configuration Required',
                  style: AppTypography.label.copyWith(
                    color: configured
                        ? AppColors.primaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminMediaPreview extends StatelessWidget {
  final Widget child;
  final String label;

  const AdminMediaPreview({
    super.key,
    required this.child,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutralLight,
        borderRadius: AppRadii.largeBorder,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.9),
                borderRadius: AppRadii.smallBorder,
              ),
              child: Text(label, style: AppTypography.caption),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminMediaActionRow extends StatelessWidget {
  final String testLabel;
  final VoidCallback onTest;
  final VoidCallback? onReplace;
  final VoidCallback? onRemove;

  const AdminMediaActionRow({
    super.key,
    required this.testLabel,
    required this.onTest,
    this.onReplace,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        OutlinedButton.icon(
          onPressed: onTest,
          icon: const Icon(Icons.science_outlined, size: AppSizes.iconSmall),
          label: Text(testLabel),
        ),
        if (onReplace != null)
          OutlinedButton.icon(
            onPressed: onReplace,
            icon: const Icon(Icons.upload_outlined, size: AppSizes.iconSmall),
            label: const Text('Replace'),
          ),
        if (onRemove != null)
          OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: AppSizes.iconSmall),
            label: const Text('Remove'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          ),
      ],
    );
  }
}
