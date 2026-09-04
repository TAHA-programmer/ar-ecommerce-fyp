import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/fields/app_text_field.dart';
import '../../../../core/widgets/fields/app_password_field.dart';
import '../../../../core/widgets/fields/app_checkbox.dart';
import '../../../../core/widgets/buttons/app_primary_button.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/models/auth/user_role.dart';
import '../viewmodels/login_viewmodel.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_divider.dart';
import '../../widgets/social_login_button.dart';
import '../../widgets/auth_footer_link.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final LoginViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback if we wanted to read from provider, but
    // to link controllers to ViewModel, we can just add listeners.
    _emailController.addListener(() {
      if (mounted) {
        context.read<LoginViewModel>().updateEmail(_emailController.text);
      }
    });
    _passwordController.addListener(() {
      if (mounted) {
        context.read<LoginViewModel>().updatePassword(_passwordController.text);
      }
    });

    // Remember Me: the ViewModel loads any saved email asynchronously, so
    // sync the field once that arrives (immediately if it's already there,
    // e.g. a previous logout on this same screen).
    _viewModel = context.read<LoginViewModel>();
    _emailController.text = _viewModel.email;
    _viewModel.addListener(_syncEmailFromViewModel);
  }

  void _syncEmailFromViewModel() {
    if (_emailController.text != _viewModel.email) {
      _emailController.text = _viewModel.email;
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_syncEmailFromViewModel);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final viewModel = context.read<LoginViewModel>();
    final result = await viewModel.submitLogin();

    if (!mounted) return;

    if (!result.success) {
      AppToast.error(
        context,
        result.errorMessage ?? 'Invalid email or password.',
      );
    } else {
      if (result.role == UserRole.superAdmin) {
        Navigator.of(context).pushReplacementNamed(RouteNames.adminDashboard);
      } else {
        Navigator.of(context).pushReplacementNamed(RouteNames.home);
      }
    }
  }

  void _handleGoogleSignIn() {
    AppToast.info(
      context,
      'Google Sign-In will be connected during authentication integration.',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Transparent status bar with dark icons
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // Responsive scaling based on a ~430px design width
    final double width = MediaQuery.of(context).size.width;
    final double scale = (width / 430.0).clamp(0.8, 1.2);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            AuthHeader(height: 280 * scale),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
              child: Column(
                children: [
                  SizedBox(height: 16 * scale),
                  RichText(
                    text: TextSpan(
                      text: 'Welcome ',
                      style: const TextStyle(
                        fontFamily: 'Playfair Display',
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                      children: [
                        TextSpan(
                          text: 'Back',
                          style: const TextStyle(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  Text(
                    'Log In to continue shopping !',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: 32 * scale),
                  AppTextField(
                    label: 'Email',
                    hint: 'Enter your email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 24 * scale),
                  AppPasswordField(
                    label: 'Password',
                    hint: 'Enter your password',
                    controller: _passwordController,
                  ),
                  SizedBox(height: 16 * scale),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Consumer<LoginViewModel>(
                        builder: (context, vm, _) {
                          return AppCheckbox(
                            labelText: 'Remember Me',
                            value: vm.isRememberMeChecked,
                            onChanged: (_) => vm.toggleRememberMe(),
                          );
                        },
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(
                            context,
                          ).pushNamed(RouteNames.forgotPassword);
                        },
                        child: Text(
                          'Forgot Password?',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 32 * scale),
                  Consumer<LoginViewModel>(
                    builder: (context, vm, _) {
                      return AppPrimaryButton(
                        label: 'Log In',
                        onPressed: _handleLogin,
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
                  const AuthDivider(text: 'or continue with'),
                  SizedBox(height: 32 * scale),
                  SocialLoginButton(onTap: _handleGoogleSignIn),
                  SizedBox(height: 32 * scale),
                  AuthFooterLink(
                    normalText: 'Don\'t have an account ? ',
                    linkText: 'Sign Up',
                    onLinkTap: () {
                      Navigator.of(context).pushNamed(RouteNames.signUp);
                    },
                  ),
                  SizedBox(height: 48 * scale),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
