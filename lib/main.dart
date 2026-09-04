import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'app/app.dart';
import 'core/config/stripe_config.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Stripe is initialised ONLY when a publishable key was supplied at build
  // time (`--dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...`). Without it the
  // checkout screen shows a "card payment unavailable" state - the rest of
  // the app is unaffected.
  if (StripeConfig.isConfigured) {
    Stripe.publishableKey = StripeConfig.publishableKey;
    await Stripe.instance.applySettings();
  }

  runApp(const TWinArApp());
}
