import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../viewmodels/splash_viewmodel.dart';
import '../../../core/constants/app_assets.dart';
import '../../../app/routes/route_names.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  late final SplashViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<SplashViewModel>();
    _viewModel.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (!mounted) return;
    if (_viewModel.state == SplashState.complete) {
      final String destination;
      if (_viewModel.isAuthenticated) {
        destination = _viewModel.isSuperAdmin
            ? RouteNames.adminDashboard
            : RouteNames.home;
      } else if (_viewModel.hasCompletedOnboarding) {
        destination = RouteNames.login;
      } else {
        destination = RouteNames.onboarding;
      }
      Navigator.of(context).pushReplacementNamed(destination);
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(AppAssets.splashBackground, fit: BoxFit.cover),
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Image.asset(AppAssets.logoMark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
