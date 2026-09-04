import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../viewmodels/onboarding_viewmodel.dart';
import '../widgets/onboarding_page.dart';
import '../widgets/onboarding_indicator.dart';
import '../widgets/onboarding_nav_button.dart';
import '../widgets/product_discovery_visual.dart';
import '../widgets/room_ar_visual.dart';
import '../widgets/virtual_try_on_visual.dart';
import '../../../app/routes/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onSkip() async {
    await context.read<OnboardingViewModel>().markOnboardingComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(RouteNames.login);
  }

  Future<void> _onComplete() async {
    await context.read<OnboardingViewModel>().markOnboardingComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(RouteNames.login);
  }

  void _onNext(OnboardingViewModel viewModel) {
    if (viewModel.isLastPage) {
      _onComplete();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onBack() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<OnboardingViewModel>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar with Skip
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.l,
                  vertical: AppSpacing.s,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _onSkip,
                      child: Text(
                        'Skip',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Page View
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: viewModel.onPageChanged,
                  children: const [
                    OnboardingPage(
                      visual: ProductDiscoveryVisual(),
                      title: 'Discover Products You Love',
                      description:
                          'Browse categories, search easily, and find the perfect products for your home & style.',
                    ),
                    OnboardingPage(
                      visual: RoomArVisual(),
                      title: 'See It In Your Space',
                      description:
                          'Place furniture & decor in your room using AR and visualize before you buy.',
                    ),
                    OnboardingPage(
                      visual: VirtualTryOnVisual(),
                      title: 'Try Before You Buy',
                      description:
                          'Virtually try on clothing and enhance confidence before you purchase.',
                    ),
                  ],
                ),
              ),
              // Bottom Navigation
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OnboardingNavButton(
                      icon: Icons.chevron_left,
                      onPressed: _onBack,
                      isVisible: !viewModel.isFirstPage,
                    ),
                    OnboardingIndicator(
                      totalPages: viewModel.totalPages,
                      currentPage: viewModel.currentPage,
                    ),
                    OnboardingNavButton(
                      icon: Icons.chevron_right,
                      onPressed: () => _onNext(viewModel),
                      isVisible: true,
                    ),
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
