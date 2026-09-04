import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/app_primary_button.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/widgets/fields/app_text_field.dart';
import '../../../../core/widgets/fields/app_password_field.dart';
import '../../../../core/widgets/fields/app_checkbox.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_footer_link.dart';
import '../viewmodels/signup_viewmodel.dart';

class SignupView extends StatefulWidget {
  const SignupView({super.key});

  @override
  State<SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends State<SignupView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSignUp() async {
    FocusScope.of(context).unfocus();

    final viewModel = context.read<SignupViewModel>();
    final result = await viewModel.validateAndSignUp(
      name: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      password: _passwordController.text,
      confirmPassword: _confirmPasswordController.text,
    );

    if (!mounted) return;

    switch (result) {
      case SignupResult.success:
        AppToast.success(context, 'Account created successfully!');
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, RouteNames.login);
        }
        break;
      case SignupResult.invalidName:
        AppToast.error(context, 'Please enter your full name.');
        break;
      case SignupResult.invalidEmail:
        AppToast.error(context, 'Please enter a valid email address.');
        break;
      case SignupResult.invalidPhone:
        AppToast.error(
          context,
          'Enter an 11-digit mobile number starting with 03.',
        );
        break;
      case SignupResult.passwordTooWeak:
        AppToast.error(
          context,
          'Password must be at least 8 characters and include an '
          'uppercase letter, a lowercase letter, a number, and a '
          'special character.',
        );
        break;
      case SignupResult.passwordMismatch:
        AppToast.error(context, 'Passwords do not match.');
        break;
      case SignupResult.termsNotAccepted:
        AppToast.error(
          context,
          'You must agree to the Terms & Conditions and Privacy Policy.',
        );
        break;
      case SignupResult.firebaseError:
        AppToast.error(
          context,
          viewModel.firebaseErrorMessage ??
              'Something went wrong. Please try again.',
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.of(context).size.width / 430;
    final screenHeight = MediaQuery.of(context).size.height;
    final textScale = scale.clamp(0.8, 1.2);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthHeader(height: screenHeight * 0.32),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 16 * scale),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: AppTypography.displayMedium.copyWith(
                          fontSize: 36 * textScale,
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                        children: const [
                          TextSpan(
                            text: 'Create ',
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                          TextSpan(
                            text: 'Account',
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      'Join TWin AR and start exploring',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 16 * textScale,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 32 * scale),

                    AppTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      hint: 'Enter your full name',
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(
                        Icons.person_outline,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 16 * scale),
                    AppTextField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'Enter your email',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 16 * scale),
                    AppTextField(
                      controller: _phoneController,
                      label: 'Phone No',
                      hint: 'e.g. 03001234567',
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      prefixIcon: const Icon(
                        Icons.phone_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 16 * scale),
                    AppPasswordField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Enter your password',
                      textInputAction: TextInputAction.next,
                    ),
                    SizedBox(height: 16 * scale),
                    AppPasswordField(
                      controller: _confirmPasswordController,
                      label: 'Confirm Password',
                      hint: 'Confirm your password',
                      textInputAction: TextInputAction.done,
                    ),
                    SizedBox(height: 24 * scale),

                    Consumer<SignupViewModel>(
                      builder: (context, viewModel, child) {
                        return AppCheckbox(
                          value: viewModel.termsAccepted,
                          onChanged: viewModel.toggleTermsAccepted,
                          labelWidget: Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: RichText(
                              text: TextSpan(
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                                children: [
                                  const TextSpan(text: 'I agree to the '),
                                  TextSpan(
                                    text: 'Terms & Conditions',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.pushNamed(
                                          context,
                                          RouteNames.terms,
                                        );
                                      },
                                  ),
                                  const TextSpan(text: ' and '),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.pushNamed(
                                          context,
                                          RouteNames.privacy,
                                        );
                                      },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 32 * scale),

                    Consumer<SignupViewModel>(
                      builder: (context, viewModel, child) {
                        return AppPrimaryButton(
                          label: 'Sign Up',
                          onPressed: viewModel.isLoading ? null : _handleSignUp,
                          isLoading: viewModel.isLoading,
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
                    SizedBox(height: 24 * scale),

                    AuthFooterLink(
                      normalText: 'Already have an account ? ',
                      linkText: 'Log In',
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
                    SizedBox(height: 24 * scale),
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
