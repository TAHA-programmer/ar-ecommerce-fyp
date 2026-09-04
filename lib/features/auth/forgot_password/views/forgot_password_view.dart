import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/fields/app_text_field.dart';
import '../../../../core/widgets/buttons/app_primary_button.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_footer_link.dart';
import '../viewmodels/forgot_password_viewmodel.dart';

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendResetLink() async {
    final viewModel = context.read<ForgotPasswordViewModel>();
    final result = await viewModel.sendResetLink(email: _emailController.text);

    if (!mounted) return;

    if (result == ForgotPasswordResult.emptyEmail) {
      AppToast.error(context, 'Please enter your email address.');
    } else if (result == ForgotPasswordResult.invalidEmail) {
      AppToast.error(context, 'Please enter a valid email address.');
    } else if (result == ForgotPasswordResult.success) {
      AppToast.success(context, 'Reset link sent. Please check your email.');
    } else if (result == ForgotPasswordResult.failure) {
      AppToast.error(
        context,
        context.read<ForgotPasswordViewModel>().failureMessage ??
            'Something went wrong. Please try again.',
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

    final double width = MediaQuery.of(context).size.width;
    final double scale = (width / 430.0).clamp(0.8, 1.2);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false, // AuthHeader handles top padding visually
        child: SingleChildScrollView(
          child: Column(
            children: [
              AuthHeader(
                height: 280 * scale,
                centerWidget: Image.asset(
                  AppAssets.forgotPasswordIllustration,
                  width:
                      width *
                      0.4, // Substantially larger than logo (Figma target)
                  fit: BoxFit.contain,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
                child: Column(
                  children: [
                    SizedBox(height: 16 * scale),
                    RichText(
                      text: const TextSpan(
                        text: 'Forgot ',
                        style: TextStyle(
                          fontFamily: 'Playfair Display',
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5,
                        ),
                        children: [
                          TextSpan(
                            text: 'Password',
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      'Enter your email and we’ll send you\n'
                      'a link to reset your password.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: 32 * scale),
                    AppTextField(
                      label: 'Email',
                      hint: 'Enter your email',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 32 * scale),
                    Consumer<ForgotPasswordViewModel>(
                      builder: (context, vm, _) {
                        return AppPrimaryButton(
                          label: 'Send Reset Link',
                          onPressed: vm.isLoading ? null : _handleSendResetLink,
                          isLoading: vm.isLoading,
                          fullWidth: true,
                          textStyle: const TextStyle(
                            fontFamily: 'Playfair Display',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 32 * scale),
                    AuthFooterLink(
                      normalText:
                          '', // Using linkText entirely for Back to Log In
                      linkText: 'Back to Log In',
                      onLinkTap: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacementNamed(
                            context,
                            RouteNames.login,
                          );
                        }
                      },
                    ),
                    SizedBox(height: 48 * scale),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
