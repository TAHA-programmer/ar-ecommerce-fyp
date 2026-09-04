import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_address_repository.dart';
import 'package:twin_ar/features/address/models/address_model.dart';

AddressDraft _draft({String fullName = 'Test User'}) => AddressDraft(
  fullName: fullName,
  phoneNumber: '1',
  addressLine1: 'L1',
  city: 'C',
  provinceOrState: 'P',
  postalCode: '0',
);

void main() {
  group('MockAddressRepository', () {
    test('the first address created automatically becomes default', () async {
      final repo = MockAddressRepository();
      final created = await repo.addAddress(_draft());
      expect(created.isDefault, isTrue);
      expect(repo.addresses.single.isDefault, isTrue);
    });

    test('a second address does not become default automatically', () async {
      final repo = MockAddressRepository();
      await repo.addAddress(_draft(fullName: 'First'));
      final second = await repo.addAddress(_draft(fullName: 'Second'));
      expect(second.isDefault, isFalse);
      expect(repo.addresses.where((a) => a.isDefault).length, 1);
    });

    test('setDefaultAddress moves the default to another address', () async {
      final repo = MockAddressRepository();
      final first = await repo.addAddress(_draft(fullName: 'First'));
      final second = await repo.addAddress(_draft(fullName: 'Second'));

      await repo.setDefaultAddress(second.id);

      final addresses = {for (final a in repo.addresses) a.id: a.isDefault};
      expect(addresses[first.id], isFalse);
      expect(addresses[second.id], isTrue);
    });

    test(
      'deleting the default reassigns to the earliest remaining address',
      () async {
        final repo = MockAddressRepository();
        final first = await repo.addAddress(_draft(fullName: 'First'));
        final second = await repo.addAddress(_draft(fullName: 'Second'));
        await repo.addAddress(_draft(fullName: 'Third'));

        expect(repo.addresses.first.id, first.id);
        await repo.deleteAddress(first.id);

        expect(repo.addresses.first.id, second.id);
        expect(repo.addresses.first.isDefault, isTrue);
      },
    );

    test('deleting the only address leaves no default', () async {
      final repo = MockAddressRepository();
      final only = await repo.addAddress(_draft());
      await repo.deleteAddress(only.id);
      expect(repo.addresses, isEmpty);
      expect(repo.defaultAddress, isNull);
    });

    test('addresses is sorted oldest-first by createdAt', () async {
      final repo = MockAddressRepository();
      final first = await repo.addAddress(_draft(fullName: 'First'));
      final second = await repo.addAddress(_draft(fullName: 'Second'));
      final third = await repo.addAddress(_draft(fullName: 'Third'));

      expect(repo.addresses.map((a) => a.id).toList(), [
        first.id,
        second.id,
        third.id,
      ]);
    });

    test('failAddAddressWith causes addAddress to throw cleanly', () async {
      final repo = MockAddressRepository()
        ..failAddAddressWith = StateError('boom');
      await expectLater(repo.addAddress(_draft()), throwsA(isA<StateError>()));
    });

    test(
      'setDefaultAddress on an unknown id throws a clean StateError',
      () async {
        final repo = MockAddressRepository();
        await expectLater(
          repo.setDefaultAddress('missing'),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
