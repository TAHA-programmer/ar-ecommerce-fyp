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
      lastUpdated: 'Last updated: October 2026',
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
              'We support secure email and password authentication, as well as Google Sign-In for faster access to the app.',
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
          title: 'Camera / Room AR Access',
          body:
              'To utilize Room AR, TWin AR requires temporary access to your device\'s camera. This video feed is processed locally on your device and is not permanently stored or transmitted.',
        ),
        LegalSectionData(
          number: 7,
          title: 'Virtual Try-On Photos',
          body:
              'Virtual Try-On works differently from Room AR: it uses a still photo, not a live camera feed. If you use Virtual Try-On, the photo you take or choose is securely uploaded and sent to Google Gemini, our third-party AI image provider, to generate your preview. Your photo is deleted immediately after the preview is generated. The generated preview image is deleted when you close it, delete it yourself, or automatically within 24 hours, whichever comes first. Virtual Try-On requires your explicit consent, given before every session, and is never used without it. You can delete any remaining Virtual Try-On photos or previews at any time from Profile > Delete My Try-On Data.',
        ),
        LegalSectionData(
          number: 8,
          title: 'Ratings and Reviews',
          body:
              'If you purchase and receive a product, you may submit a rating and written review for it. A published review shows a masked version of your name (for example, "Ayesha K.") — never your email, phone number, or other account details — and is visible to other users viewing that product. Other users may report a review they believe is spam, offensive, or fake; reported reviews are queued for our team to review, and we may hide or remove content that violates these Terms.',
        ),
        LegalSectionData(
          number: 9,
          title: 'Push Notifications',
          body:
              'Push notifications are optional. If you allow them, we store a device notification token (an identifier issued by Google Firebase Cloud Messaging for your phone) together with your app version and a random installation ID, linked to your account, so we can send updates to this device. We also store your notification preferences and keep a history of your order, refund and review-moderation updates in the Notification Centre inside the app. We send updates when your order is confirmed, shipped, delivered or cancelled, if a payment could not be turned into an order and was refunded, and if a review of yours is hidden or not published. Notifications show only a short order reference - never your address, items, or payment details. We ask for permission only at a relevant moment, never when you first open the app, and you can turn each category off any time in Notification settings or in your phone settings; turning a category off stops the push but your Notification Centre still records the update. When you log out, we ask our servers to remove your device token and we invalidate it on your phone, so notifications for your account stop arriving there; if that request cannot be completed (for example while you are offline), the leftover record is cleaned up automatically when a delivery to it fails or when it expires. Device tokens are also deleted if your account is deleted. Notification Centre entries are kept for a limited period (about 90 days). Push delivery is not guaranteed - your phone, battery saver or network may delay or block it - so your orders in My Orders are always the up-to-date record.',
        ),
        LegalSectionData(
          number: 10,
          title: 'Third-Party Services',
          body:
              'We may employ third-party companies and services, such as Firebase for backend infrastructure and Firebase Cloud Messaging for push notifications, Stripe for payments, and Google Gemini for Virtual Try-On image generation, to facilitate our application. These third parties have access to your Personal Data only to perform these tasks on our behalf.',
        ),
        LegalSectionData(
          number: 11,
          title: 'Data Security',
          body:
              'We value your trust in providing us your Personal Information, thus we are striving to use commercially acceptable means of protecting it. But remember that no method of transmission over the internet, or method of electronic storage is 100% secure.',
        ),
        LegalSectionData(
          number: 12,
          title: 'Data Retention',
          body:
              'Your data is retained only for as long as necessary to provide you with our services and for legitimate and essential business purposes, such as maintaining the performance of the app. See "Virtual Try-On Photos" above for the specific retention rules that apply to Virtual Try-On images.',
        ),
        LegalSectionData(
          number: 13,
          title: 'User Choices and Rights',
          body:
              'You have the right to update or delete your account information at any time. Permissions such as camera access can also be managed directly through your device settings.',
        ),
        LegalSectionData(
          number: 14,
          title: 'Changes to This Policy',
          body:
              'We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page.',
        ),
        LegalSectionData(
          number: 15,
          title: 'Contact Us',
          body:
              'If you have any questions or suggestions about our Privacy Policy, do not hesitate to contact the TWin AR support team.',
        ),
      ],
    );
  }
}
