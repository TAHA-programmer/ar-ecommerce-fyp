import 'package:flutter/material.dart';
import '../../widgets/legal_screen_scaffold.dart';

class PrivacyPolicyView extends StatelessWidget {
  const PrivacyPolicyView({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreenScaffold(
      title: 'Privacy Policy',
      subtitle:
          'Learn how TWin AR collects, uses, and protects your information.',
      lastUpdated: 'Last updated: August 2026',
      sections: [
        LegalSectionData(
          number: 1,
          title: 'Information We Collect',
          body:
              'We may collect personal information such as your full name, email address, phone number, account-related information, and order-related details when you use our services.',
        ),
        LegalSectionData(
          number: 2,
          title: 'How We Use Information',
          body:
              'The information collected is used to create and manage accounts, support shopping and order flows, improve your overall user experience, and facilitate AR and virtual try-on features.',
        ),
        LegalSectionData(
          number: 3,
          title: 'Authentication',
          body:
              'We support secure email and password authentication. Additionally, third-party authentication methods such as Google Sign-In may be integrated to streamline your access to the app.',
        ),
        LegalSectionData(
          number: 4,
          title: 'Orders and Shopping Data',
          body:
              'Your cart contents, purchase history, and specific order details may be stored to provide a continuous and personalized shopping experience.',
        ),
        LegalSectionData(
          number: 5,
          title: 'Payments',
          body:
              'Payment-related flows are processed securely by Stripe. We do not directly retain sensitive payment details like your full credit card number.',
        ),
        LegalSectionData(
          number: 6,
          title: 'Camera / AR Access',
          body:
              'To utilize room AR and virtual try-on features, TWin AR requires temporary access to your device\'s camera. This video feed is processed locally and is not permanently stored or transmitted.',
        ),
        LegalSectionData(
          number: 7,
          title: 'Third-Party Services',
          body:
              'We may employ third-party companies and services, such as Firebase for backend infrastructure and Stripe for payments, to facilitate our application. These third parties have access to your Personal Data only to perform these tasks on our behalf.',
        ),
        LegalSectionData(
          number: 8,
          title: 'Data Security',
          body:
              'We value your trust in providing us your Personal Information, thus we are striving to use commercially acceptable means of protecting it. But remember that no method of transmission over the internet, or method of electronic storage is 100% secure.',
        ),
        LegalSectionData(
          number: 9,
          title: 'Data Retention',
          body:
              'Your data is retained only for as long as necessary to provide you with our services and for legitimate and essential business purposes, such as maintaining the performance of the app.',
        ),
        LegalSectionData(
          number: 10,
          title: 'User Choices and Rights',
          body:
              'You have the right to update or delete your account information at any time. Permissions such as camera access can also be managed directly through your device settings.',
        ),
        LegalSectionData(
          number: 11,
          title: 'Changes to This Policy',
          body:
              'We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page.',
        ),
        LegalSectionData(
          number: 12,
          title: 'Contact Us',
          body:
              'If you have any questions or suggestions about our Privacy Policy, do not hesitate to contact the TWin AR support team.',
        ),
      ],
    );
  }
}
