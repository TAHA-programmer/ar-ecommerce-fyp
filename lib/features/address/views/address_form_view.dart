import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/viewmodels/customer_address_state.dart';
import '../viewmodels/address_form_viewmodel.dart';
import '../models/address_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fields/app_text_field.dart';
import '../../../core/widgets/fields/app_checkbox.dart';
import '../../../core/widgets/buttons/app_primary_button.dart';
import '../../../core/widgets/feedback/app_toast.dart';

class AddressFormView extends StatelessWidget {
  const AddressFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final initialAddress =
        ModalRoute.of(context)?.settings.arguments as AddressModel?;

    return ChangeNotifierProvider(
      create: (context) => AddressFormViewModel(
        context.read<CustomerAddressState>(),
        initialAddress: initialAddress,
      ),
      child: const _AddressFormContent(),
    );
  }
}

class _AddressFormContent extends StatelessWidget {
  const _AddressFormContent();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AddressFormViewModel>();
    final isEditing = viewModel.isEditing;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isEditing),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: viewModel.formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Enter your delivery details below.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppTextField(
                        label: 'Address Label (Optional)',
                        hint: 'e.g. Home, Work',
                        controller: viewModel.labelController,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Full Name',
                        hint: 'Enter your full name',
                        controller: viewModel.fullNameController,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Phone Number',
                        hint: 'Enter your phone number',
                        controller: viewModel.phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Address Line 1',
                        hint: 'House, Street, etc.',
                        controller: viewModel.addressLine1Controller,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Address Line 2 (Optional)',
                        hint: 'Apartment, Suite, etc.',
                        controller: viewModel.addressLine2Controller,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              label: 'City',
                              hint: 'City',
                              controller: viewModel.cityController,
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: AppTextField(
                              label: 'Province / State',
                              hint: 'Province',
                              controller: viewModel.provinceController,
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Postal Code',
                        hint: 'Postal Code',
                        controller: viewModel.postalCodeController,
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.number,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      AppCheckbox(
                        labelText: 'Set as default address',
                        value: viewModel.isDefault,
                        onChanged: viewModel.toggleDefault,
                      ),
                      const SizedBox(height: 32),
                      AppPrimaryButton(
                        label: isEditing ? 'Update Address' : 'Save Address',
                        onPressed: viewModel.isSaving
                            ? null
                            : () async {
                                final result = await viewModel.save();
                                if (!context.mounted) return;
                                if (result.shouldNavigateBack) {
                                  Navigator.pop(context);
                                } else if (result.shouldShowError) {
                                  AppToast.error(context, result.errorMessage!);
                                }
                                // validationFailed/inProgress: stay on screen,
                                // no toast - the Form's own inline field
                                // errors already show the problem.
                              },
                        fullWidth: true,
                        textStyle: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primaryDark,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32), // Keyboard padding
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

  Widget _buildHeader(BuildContext context, bool isEditing) {
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
            isEditing ? 'Edit Address' : 'Add New Address',
            style: AppTypography.headingMedium,
          ),
        ],
      ),
    );
  }
}
