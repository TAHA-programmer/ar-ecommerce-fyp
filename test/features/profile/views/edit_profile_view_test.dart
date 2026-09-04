import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/core/widgets/fields/app_text_field.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/viewmodels/edit_profile_viewmodel.dart';
import 'package:twin_ar/features/profile/views/edit_profile_view.dart';

const _uid = 'test-uid';

Future<CustomerProfileState> _loadedProfileState() async {
  final repository = MockUserProfileRepository(
    seed: {
      _uid: const UserProfileModel(
        uid: _uid,
        email: 'neha.sharma@gmail.com',
        displayName: 'Neha Sharma',
        phone: '+91 98765 43210',
        role: 'customer',
      ),
    },
  );
  final state = CustomerProfileState(repository);
  await state.loadForUser(_uid);
  return state;
}

void main() {
  Widget createTestWidget(CustomerProfileState profileState) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CustomerProfileState>.value(value: profileState),
        ChangeNotifierProxyProvider<CustomerProfileState, EditProfileViewModel>(
          create: (context) =>
              EditProfileViewModel(context.read<CustomerProfileState>()),
          update: (context, profileState, _) =>
              EditProfileViewModel(profileState),
        ),
      ],
      child: const MaterialApp(home: EditProfileView()),
    );
  }

  testWidgets('EditProfileView renders form fields and pre-fills them', (
    WidgetTester tester,
  ) async {
    final profileState = await _loadedProfileState();
    await tester.pumpWidget(createTestWidget(profileState));
    await tester.pumpAndSettle();

    // Check header
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios), findsOneWidget);

    // Check fields pre-filled from the loaded profile
    expect(find.text('Neha Sharma'), findsOneWidget);
    expect(find.text('neha.sharma@gmail.com'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);

    // Check buttons
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('Email field is disabled and cannot be edited', (
    WidgetTester tester,
  ) async {
    final profileState = await _loadedProfileState();
    await tester.pumpWidget(createTestWidget(profileState));
    await tester.pumpAndSettle();

    final emailField = tester.widget<AppTextField>(
      find.widgetWithText(AppTextField, 'Email'),
    );

    expect(emailField.enabled, isFalse);
    expect(emailField.onChanged, isNull);
  });
}
