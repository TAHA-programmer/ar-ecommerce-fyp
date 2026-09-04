import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';

/// Minimal controllable [AuthRepository] fake for exercising
/// [AuthSessionState]'s reactive subscription without any Firebase
/// dependency.
class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthResult?>.broadcast();

  void emit(AuthResult? result) => _controller.add(result);
  void emitError(Object error) => _controller.addError(error);

  @override
  Stream<AuthResult?> authStateChanges() => _controller.stream;

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async => AuthResult.failure(errorMessage: 'not used');

  @override
  Future<String?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String phone,
  }) async => null;

  @override
  Future<void> signOut() async {}

  @override
  Future<String?> sendPasswordResetEmail({required String email}) async => null;

  void dispose() => _controller.close();
}

void main() {
  group('AuthSessionState - no repository (legacy/manual-session usage)', () {
    test('ready completes immediately', () async {
      final state = AuthSessionState();
      await expectLater(state.ready, completes);
      expect(state.isAuthenticated, isFalse);
    });

    test('setSession/clearSession behave exactly as before', () {
      final state = AuthSessionState();
      state.setSession(
        AuthResult.success(
          userId: 'u1',
          email: 'test@example.com',
          role: UserRole.customer,
        ),
      );
      expect(state.isAuthenticated, isTrue);
      expect(state.isCustomer, isTrue);

      state.clearSession();
      expect(state.isAuthenticated, isFalse);
    });
  });

  group('AuthSessionState - with repository (production path)', () {
    late _FakeAuthRepository repository;

    setUp(() {
      repository = _FakeAuthRepository();
    });

    tearDown(() {
      repository.dispose();
    });

    test('ready completes once the first auth-state event arrives', () async {
      final state = AuthSessionState(repository);
      addTearDown(state.dispose);

      expect(state.ready, completion(isNull));
      repository.emit(null);
      await state.ready;
      expect(state.isAuthenticated, isFalse);
    });

    test('reflects a signed-in emission automatically', () async {
      final state = AuthSessionState(repository);
      addTearDown(state.dispose);

      repository.emit(
        AuthResult.success(
          userId: 'u2',
          email: 'shopper@example.com',
          role: UserRole.customer,
        ),
      );
      await state.ready;

      expect(state.isAuthenticated, isTrue);
      expect(state.userId, 'u2');
      expect(state.isCustomer, isTrue);
    });

    test('clears the session on a signed-out (null) emission', () async {
      final state = AuthSessionState(repository);
      addTearDown(state.dispose);

      repository.emit(
        AuthResult.success(
          userId: 'u3',
          email: 'shopper@example.com',
          role: UserRole.customer,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(state.isAuthenticated, isTrue);

      repository.emit(null);
      await Future<void>.delayed(Duration.zero);
      expect(state.isAuthenticated, isFalse);
    });

    test(
      'a stream error is treated as signed-out and still resolves ready',
      () async {
        final state = AuthSessionState(repository);
        addTearDown(state.dispose);

        repository.emitError(Exception('boom'));
        await state.ready;

        expect(state.isAuthenticated, isFalse);
      },
    );
  });
}
