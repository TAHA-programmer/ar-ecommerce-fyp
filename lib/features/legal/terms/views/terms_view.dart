import 'package:flutter/material.dart';
import '../../widgets/legal_screen_scaffold.dart';

class TermsView extends StatelessWidget {
  const TermsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreenScaffold(
      title: 'Terms & Conditions',
      subtitle: 'Please read these terms carefully before using TWin AR.',
      lastUpdated: 'Last updated: August 2026',
      sections: [
        LegalSectionData(
          number: 1,
          title: 'Acceptance of Terms',
          body:
              'By accessing or using the TWin AR application, you agree to be bound by these Terms & Conditions. If you do not agree with any part of these terms, you may not use our services.',
        ),
        LegalSectionData(
          number: 2,
          title: 'User Accounts',
          body:
              'You must provide accurate and complete information when creating an account. You are responsible for safeguarding your login credentials and for any activities or actions under your account.',
        ),
        LegalSectionData(
          number: 3,
          title: 'Products and Information',
          body:
              'We strive to present product descriptions, images, colors, sizes, and dimensions as accurately as possible. However, minor variations may occur, and we do not warrant that product descriptions are entirely error-free.',
        ),
        LegalSectionData(
          number: 4,
          title: 'Orders and Pricing',
          body:
              'All prices and availability of products are subject to change without notice. Orders are subject to stock availability and formal confirmation of the purchase.',
        ),
        LegalSectionData(
          number: 5,
          title: 'Payments',
          body:
              'Payments within the application are securely processed through Stripe. We do not directly store your full credit card information on our servers.',
        ),
        LegalSectionData(
          number: 6,
          title: 'AR and Virtual Try-On Disclaimer',
          body:
              'The AR room placement and virtual try-on features are visualization aids only. Real-life appearance, fit, scale, and color may vary from the digital representation on your device screen.',
        ),
        LegalSectionData(
          number: 7,
          title: 'User Responsibilities',
          body:
              'Users agree not to misuse the application, attempt unauthorized access, or use the application for any illegal or unauthorized purpose.',
        ),
        LegalSectionData(
          number: 8,
          title: 'Intellectual Property',
          body:
              'The TWin AR branding, interface, and original content are the property of their respective owners and are protected by applicable intellectual property laws.',
        ),
        LegalSectionData(
          number: 9,
          title: 'Returns, Cancellations, and Refunds',
          body:
              'Specific policies regarding returns, cancellations, and refunds are governed by the final store policy associated with the purchased item.',
        ),
        LegalSectionData(
          number: 10,
          title: 'Changes to Terms',
          body:
              'We reserve the right to modify or replace these Terms & Conditions at any time. Your continued use of the application following the posting of any changes constitutes acceptance of those changes.',
        ),
        LegalSectionData(
          number: 11,
          title: 'Contact / Support',
          body:
              'For support or questions regarding these Terms & Conditions, please contact the TWin AR support team.',
        ),
      ],
    );
  }
}
