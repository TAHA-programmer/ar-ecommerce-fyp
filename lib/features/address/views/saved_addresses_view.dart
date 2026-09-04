import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/viewmodels/customer_address_state.dart';
import '../../../app/routes/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../viewmodels/saved_addresses_viewmodel.dart';
import '../widgets/address_card.dart';
import '../widgets/address_empty_state.dart';
import '../models/address_model.dart';
import '../../../core/widgets/feedback/app_toast.dart';

class SavedAddressesView extends StatelessWidget {
  const SavedAddressesView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          SavedAddressesViewModel(context.read<CustomerAddressState>()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Consumer<SavedAddressesViewModel>(
                  builder: (context, viewModel, child) {
                    final addressState = context.watch<CustomerAddressState>();
                    if (addressState.addresses.isEmpty) {
                      return const AddressEmptyState(
                        title: 'No saved addresses yet',
                        subtitle: 'Add an address to make checkout faster.',
                      );
                    }
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final addressState = context
                                    .read<CustomerAddressState>();
                                final address = addressState.addresses[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: AddressCard(
                                    address: address,
                                    isSelected:
                                        false, // Not applicable in account mode
                                    isAccountMode: true,
                                    onSelect:
                                        () {}, // Not applicable in account mode
                                    onSetDefault: () {
                                      viewModel.setDefault(address.id).then((
                                        error,
                                      ) {
                                        if (error != null && context.mounted) {
                                          AppToast.error(context, error);
                                        }
                                      });
                                    },
                                    onEdit: () =>
                                        _confirmEdit(context, address),
                                    onDelete: () => _confirmDelete(
                                      context,
                                      viewModel,
                                      address.id,
                                    ),
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
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: SizedBox(
                              height: 48,
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.pushNamed(
                                    context,
                                    RouteNames.addressForm,
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryDark,
                                  side: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Add New Address',
                                      style: AppTypography.bodySmall.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(
                            height: 100,
                          ), // padding for bottom scroll
                        ),
                      ],
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
          Text('Saved Addresses', style: AppTypography.headingMedium),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext pageContext,
    SavedAddressesViewModel viewModel,
    String id,
  ) {
    showDialog(
      context: pageContext,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        title: Text('Delete Address?', style: AppTypography.title),
        content: Text(
          'Are you sure you want to remove this address?',
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
            child: const Text('Delete'),
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
