import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/info_screen_scaffold.dart';
import '../../../core/constants/app_contact.dart';
import '../../../core/services/mail_launcher_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';

class HelpSupportView extends StatelessWidget {
  const HelpSupportView({super.key});

  Future<void> _contactSupport(BuildContext context) async {
    final launched = await context
        .read<MailLauncherService>()
        .launchSupportEmail();
    if (!context.mounted) return;
    if (launched) {
      AppToast.success(context, 'Opening your email app...');
    } else {
      AppToast.error(
        context,
        "Couldn't open an email app. Please email "
        "${AppContact.supportEmail} directly.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InfoScreenScaffold(
      title: 'Help & Support',
      subtitle: 'How can we help?',
      sections: const [
        InfoSectionData(
          title: 'How do I place an order?',
          body:
              'Browse products, add items to your cart, select a delivery address, review your order, and proceed to secure payment.',
        ),
        InfoSectionData(
          title: 'How do I change my delivery address?',
          body:
              'Saved delivery addresses can be managed from your account. During checkout, select the address you want to use.',
        ),
        InfoSectionData(
          title: 'How do I use Room AR?',
          body:
              'Open an AR-supported furniture, rug, decor, or lighting product and choose the Room AR option.',
        ),
        InfoSectionData(
          title: 'How do I use Virtual Try-On?',
          body:
              'Open a supported clothing product and choose Try It On, then follow the positioning instructions.',
        ),
        InfoSectionData(
          title: 'How do I leave a rating or review?',
          body:
              'Once your order is delivered, open the product page or that order in My Orders and choose Write a Review to share your rating and feedback.',
        ),
        InfoSectionData(
          title: 'How do I view my orders?',
          body:
              'Your placed orders will be available through My Orders in your Profile.',
        ),
        InfoSectionData(
          title: 'How do payments work?',
          body:
              'TWin AR uses secure Stripe card payments. Cash on Delivery is not supported.',
        ),
      ],
      contactSection: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.neutralLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              'Contact Support',
              style: AppTypography.headingLarge.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 16),
            const Text(
              'Email Support',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: AppColors.textPrimary),
            ),
            const SelectableText(
              AppContact.supportEmail,
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Response Time\nUsually within 24–48 hours',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _contactSupport(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(
                'Contact Support',
                style: AppTypography.label.copyWith(color: AppColors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
