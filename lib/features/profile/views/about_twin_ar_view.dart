import 'package:flutter/material.dart';
import '../widgets/info_screen_scaffold.dart';
import '../../../core/theme/app_colors.dart';

class AboutTwinArView extends StatelessWidget {
  const AboutTwinArView({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoScreenScaffold(
      title: 'About TWin AR',
      subtitle:
          'TWin AR is an augmented-reality e-commerce application designed to make online shopping more interactive and informative.',
      sections: const [
        InfoSectionData(
          title: 'What TWin AR Offers',
          body:
              '• Room AR\nPreview supported furniture, rugs, decor, and lighting in your environment before purchasing.\n\n• Virtual Try-On\nPreview supported clothing products using the Virtual Try-On experience.\n\n• Smart Shopping\nBrowse products, manage your cart, choose delivery addresses, place orders, and complete secure card payments.',
        ),
        InfoSectionData(
          title: 'Our Goal',
          body:
              'TWin AR combines traditional e-commerce with immersive AR experiences to help customers make more confident purchase decisions.',
        ),
        InfoSectionData(
          title: 'Secure Payments',
          body: 'Payments are designed to be handled securely through Stripe.',
        ),
        InfoSectionData(title: 'Version', body: '1.0.0'),
      ],
      contactSection: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Image.asset(
            'assets/images/logo/twin_ar_logo.png',
            height: 60,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.camera_alt,
              size: 60,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
