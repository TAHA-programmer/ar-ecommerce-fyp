import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../app/routes/route_names.dart';
import '../../../app/viewmodels/customer_profile_state.dart';
import '../../../app/viewmodels/auth_session_state.dart';
import '../../../features/auth/repositories/auth_repository.dart';
import '../../../core/services/device_image_picker_service.dart';
import '../../virtual_try_on/services/virtual_try_on_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../../../core/widgets/navigation/customer_bottom_navigation.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/profile_menu_item.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  void _showImagePickerBottomSheet(
    BuildContext context,
    CustomerProfileState state,
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
                  final error = await state.uploadAvatar(File(path));
                  if (error != null && context.mounted) {
                    AppToast.error(context, error);
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
                  final error = await state.uploadAvatar(File(path));
                  if (error != null && context.mounted) {
                    AppToast.error(context, error);
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

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mediumBorder,
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        title: Text('Log Out?', style: AppTypography.title),
        content: Text(
          'Are you sure you want to log out?',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final authRepo = context.read<AuthRepository>();
    final authState = context.read<AuthSessionState>();

    await authRepo.signOut();
    authState.clearSession();

    if (context.mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
    }
  }

  /// Phase 9.3 Stage 5 (tracker §5.2 step 10 / D4) — removes every Virtual
  /// Try-On Storage object (person-photo uploads + generated previews) this
  /// customer owns. `tryOnSessions` activity records (which colour/product/
  /// timestamp — no photos) are NOT client-deletable (`firestore.rules`) and
  /// are left in place; only the media is deleted here. Shows truthful
  /// success / partial-failure / failure feedback based on
  /// [VirtualTryOnDataDeletionResult] — never claims success when the
  /// underlying query or a Storage delete genuinely failed.
  Future<void> _confirmDeleteTryOnData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mediumBorder,
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        title: Text('Delete My Try-On Data?', style: AppTypography.title),
        content: Text(
          'This removes any saved Virtual Try-On photos and previews from '
          'your account. This cannot be undone. A record that you used '
          'Virtual Try-On (with no photos) may still be kept briefly for '
          'your account activity.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final uid = context.read<AuthSessionState>().userId;
    if (uid == null) return;

    final result = await context.read<VirtualTryOnService>().deleteAllTryOnData(
      uid: uid,
    );

    if (!context.mounted) return;
    switch (result.outcome) {
      case VirtualTryOnDataDeletionOutcome.success:
        AppToast.success(
          context,
          result.sessionsFound == 0
              ? 'No saved Virtual Try-On photos or previews were found.'
              : 'Your Virtual Try-On photos and previews have been deleted.',
        );
      case VirtualTryOnDataDeletionOutcome.partial:
        AppToast.warning(
          context,
          'Some Virtual Try-On data could not be deleted. Please try again '
          'later.',
        );
      case VirtualTryOnDataDeletionOutcome.failed:
        AppToast.error(
          context,
          "We couldn't delete your Virtual Try-On data right now. Please "
          "check your connection and try again.",
        );
    }
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
            // Header (No back button)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Row(
                children: [
                  Text(
                    'Profile',
                    style: const TextStyle(
                      fontFamily: 'Playfair Display',
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    // Profile Card
                    Consumer<CustomerProfileState>(
                      builder: (context, profileState, child) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Stack(
                                    children: [
                                      AvatarCircle(
                                        radius: 36,
                                        bytes: profileState.avatarBytes,
                                        isLoading: profileState.isAvatarLoading,
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: GestureDetector(
                                          onTap: profileState.isAvatarLoading
                                              ? null
                                              : () =>
                                                    _showImagePickerBottomSheet(
                                                      context,
                                                      profileState,
                                                    ),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          profileState.fullName,
                                          style: const TextStyle(
                                            fontFamily: 'Playfair Display',
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.email_outlined,
                                              size: 12,
                                              color: AppColors.primary,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                profileState.email,
                                                style: AppTypography.bodySmall,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.phone_outlined,
                                              size: 12,
                                              color: AppColors.primary,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                profileState.phoneNumber,
                                                style: AppTypography.bodySmall,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    RouteNames.editProfile,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.primary,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Edit Profile',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.edit,
                                        size: 11,
                                        color: AppColors.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // Menu Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ProfileMenuItem(
                            icon: Icons.shopping_bag_outlined,
                            title: 'My Orders',
                            onTap: () =>
                                Navigator.pushNamed(context, RouteNames.orders),
                          ),
                          ProfileMenuItem(
                            icon: Icons.location_on_outlined,
                            title: 'Saved Addresses',
                            onTap: () => Navigator.pushNamed(
                              context,
                              RouteNames.savedAddresses,
                            ),
                          ),
                          ProfileMenuItem(
                            icon: Icons.headset_mic_outlined,
                            title: 'Help and Support',
                            onTap: () => Navigator.pushNamed(
                              context,
                              RouteNames.helpSupport,
                            ),
                          ),
                          ProfileMenuItem(
                            icon: Icons.view_in_ar_outlined,
                            title: 'How Room AR Works',
                            onTap: () => Navigator.pushNamed(
                              context,
                              RouteNames.roomArInfo,
                            ),
                          ),
                          // Phase 9.2 R5 — internal Tier-2 Marker-AR engine
                          // verification surface. Debug builds only; compiled
                          // out of release. Not a customer AR entry point.
                          if (kDebugMode)
                            ProfileMenuItem(
                              icon: Icons.center_focus_strong_outlined,
                              title: 'Marker-AR engine (dev)',
                              onTap: () => Navigator.pushNamed(
                                context,
                                RouteNames.roomArMarkerEngine,
                              ),
                            ),
                          ProfileMenuItem(
                            icon: Icons.checkroom_outlined,
                            title: 'How Virtual Try-On Works',
                            onTap: () => Navigator.pushNamed(
                              context,
                              RouteNames.virtualTryOnInfo,
                            ),
                          ),
                          ProfileMenuItem(
                            icon: Icons.delete_outline,
                            title: 'Delete My Try-On Data',
                            onTap: () => _confirmDeleteTryOnData(context),
                          ),
                          ProfileMenuItem(
                            icon: Icons.shield_outlined,
                            title: 'Privacy Policy',
                            onTap: () => Navigator.pushNamed(
                              context,
                              RouteNames.privacy,
                            ),
                          ),
                          ProfileMenuItem(
                            icon: Icons.description_outlined,
                            title: 'Terms and Conditions',
                            onTap: () =>
                                Navigator.pushNamed(context, RouteNames.terms),
                          ),
                          ProfileMenuItem(
                            icon: Icons.info_outline,
                            title: 'About TWin AR',
                            onTap: () => Navigator.pushNamed(
                              context,
                              RouteNames.aboutTwinAr,
                            ),
                          ),
                          ProfileMenuItem(
                            icon: Icons.logout_outlined,
                            title: 'Log Out',
                            onTap: () => _confirmLogout(context),
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 120), // Bottom padding for nav
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const CustomerBottomNavigation(selectedIndex: 3),
      extendBody: true,
    );
  }
}
