import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/viewmodels/customer_address_state.dart';
import '../../../app/routes/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../viewmodels/delivery_address_viewmodel.dart';
import '../widgets/address_card.dart';
import '../widgets/address_empty_state.dart';
import '../models/address_model.dart';
import '../../../core/widgets/feedback/app_toast.dart';

class DeliveryAddressView extends StatelessWidget {
  const DeliveryAddressView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          DeliveryAddressViewModel(context.read<CustomerAddressState>()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Consumer<DeliveryAddressViewModel>(
                  builder: (context, viewModel, child) {
                    if (viewModel.isEmpty) {
                      return const AddressEmptyState();
                    }
                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildTopBanner()),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final addressState = context
                                    .read<CustomerAddressState>();
                                final address = addressState.addresses[index];
                                return AddressCard(
                                  address: address,
                                  isSelected:
                                      addressState.selectedAddressId ==
                                      address.id,
                                  onSelect: () =>
                                      viewModel.selectAddress(address.id),
                                  onSetDefault: () {
                                    viewModel.setDefault(address.id).then((
                                      error,
                                    ) {
                                      if (error != null && context.mounted) {
                                        AppToast.error(context, error);
                                      }
                                    });
                                  },
                                  onEdit: () => _confirmEdit(context, address),
                                  onDelete: () => _confirmDelete(
                                    context,
                                    viewModel,
                                    address.id,
                                  ),
                                );
                              },
                              childCount: context
                                  .watch<CustomerAddressState>()
                                  .addresses
                                  .length,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(
                            height: 100,
                          ), // padding for bottom buttons
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Consumer<DeliveryAddressViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isEmpty) return const SizedBox.shrink();
            return _buildBottomActions(context, viewModel);
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withAlpha(13),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Delivery Address',
            style: AppTypography
                .headingMedium, // Should map to Playfair Display as requested if headingMedium is Playfair
          ),
        ],
      ),
    );
  }

  Widget _buildTopBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withAlpha(77),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_outlined,
              color: AppColors.primaryDark,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where should we deliver?',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a delivery address to proceed\nwith your order.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(
    BuildContext context,
    DeliveryAddressViewModel viewModel,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, RouteNames.addressForm);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Add New Address',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: viewModel.hasSelectedAddress
                      ? () {
                          Navigator.pushNamed(context, RouteNames.checkout);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          'Proceed to Checkout',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios, size: 14),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext pageContext,
    DeliveryAddressViewModel viewModel,
    String id,
  ) {
    showDialog(
      context: pageContext,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        title: Text('Remove Address?', style: AppTypography.title),
        content: Text(
          'Are you sure you want to remove this saved address?',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              viewModel.deleteAddress(id).then((error) {
                if (error != null && pageContext.mounted) {
                  AppToast.error(pageContext, error);
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _confirmEdit(BuildContext context, AddressModel address) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        title: Text('Edit Address?', style: AppTypography.title),
        content: Text(
          'Are you sure you want to edit this saved address?',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pushNamed(
                context,
                RouteNames.addressForm,
                arguments: address,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}
