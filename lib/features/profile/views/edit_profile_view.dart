import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/device_image_picker_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fields/app_text_field.dart';
import '../../../core/widgets/buttons/app_primary_button.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../viewmodels/edit_profile_viewmodel.dart';
import '../widgets/avatar_circle.dart';

class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<EditProfileViewModel>();
    _nameController = TextEditingController(text: viewModel.draftFullName);
    _emailController = TextEditingController(text: viewModel.email);
    _phoneController = TextEditingController(text: viewModel.draftPhoneNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showImagePickerBottomSheet(
    BuildContext context,
    EditProfileViewModel viewModel,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutralLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Change Profile Photo',
                style: AppTypography.title.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: AppColors.primary,
                ),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final path = await DeviceImagePickerService()
                      .pickImageFromGallery();
                  if (path == null) return; // cancelled/denied - not an error
                  await viewModel.uploadAvatar(File(path));
                  if (context.mounted && viewModel.avatarError != null) {
                    AppToast.error(context, viewModel.avatarError!);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final path = await DeviceImagePickerService()
                      .pickImageFromCamera();
                  if (path == null) return; // cancelled/denied - not an error
                  await viewModel.uploadAvatar(File(path));
                  if (context.mounted && viewModel.avatarError != null) {
                    AppToast.error(context, viewModel.avatarError!);
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.close,
                  color: AppColors.textSecondary,
                ),
                title: const Text('Cancel'),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontFamily: 'Playfair Display',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // Balance for centering
                ],
              ),
            ),
            Expanded(
              child: Consumer<EditProfileViewModel>(
                builder: (context, viewModel, child) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        // Editable Avatar
                        Center(
                          child: Stack(
                            children: [
                              AvatarCircle(
                                radius: 50,
                                bytes: viewModel.avatarBytes,
                                isLoading: viewModel.isAvatarUploading,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: viewModel.isAvatarUploading
                                      ? null
                                      : () => _showImagePickerBottomSheet(
                                          context,
                                          viewModel,
                                        ),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 48),
                        // Fields
                        AppTextField(
                          controller: _nameController,
                          label: 'Full Name',
                          hint: 'Enter your full name',
                          prefixIcon: const Icon(Icons.person_outline),
                          errorText: viewModel.nameError,
                          onChanged: viewModel.updateName,
                        ),
                        const SizedBox(height: 24),
                        AppTextField(
                          controller: _emailController,
                          label: 'Email',
                          hint: 'Enter your email',
                          prefixIcon: const Icon(Icons.email_outlined),
                          keyboardType: TextInputType.emailAddress,
                          enabled: false,
                        ),
                        const SizedBox(height: 24),
                        AppTextField(
                          controller: _phoneController,
                          label: 'Phone Number',
                          hint: 'e.g. 03001234567',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          errorText: viewModel.phoneError,
                          onChanged: viewModel.updatePhone,
                        ),
                        const SizedBox(height: 48),
                        AppPrimaryButton(
                          label: 'Save Changes',
                          isLoading: viewModel.isLoading,
                          onPressed: () async {
                            final success = await viewModel.saveChanges();
                            if (!context.mounted) return;
                            if (success) {
                              AppToast.success(
                                context,
                                'Profile updated successfully',
                              );
                              Navigator.pop(context);
                            } else if (viewModel.saveError != null) {
                              AppToast.error(context, viewModel.saveError!);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context); // Discard changes
                          },
                          style: TextButton.styleFrom(
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
