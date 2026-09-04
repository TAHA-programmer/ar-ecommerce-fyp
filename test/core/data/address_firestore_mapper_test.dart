import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/address_firestore_mapper.dart';
import 'package:twin_ar/features/address/models/address_model.dart';

void main() {
  group('address_firestore_mapper', () {
    test('round-trips a real address draft through toFirestoreCreateMap/'
        'addressModelFromFirestore', () {
      const draft = AddressDraft(
        label: 'Home',
        fullName: 'Jane Doe',
        phoneNumber: '03001234567',
        addressLine1: '123 Main St',
        addressLine2: 'Apt 4',
        city: 'Lahore',
        provinceOrState: 'Punjab',
        postalCode: '54000',
      );

      // toFirestoreCreateMap uses FieldValue.serverTimestamp() for
      // createdAt, which addressModelFromFirestore can't decode directly -
      // substitute a real Timestamp to isolate the field-mapping round trip.
      final map = draft.toFirestoreCreateMap();
      map['createdAt'] = Timestamp.fromDate(DateTime(2026, 1, 1));

      final restored = addressModelFromFirestore('addr1', map, null);

      expect(restored.id, 'addr1');
      expect(restored.label, draft.label);
      expect(restored.fullName, draft.fullName);
      expect(restored.phoneNumber, draft.phoneNumber);
      expect(restored.addressLine1, draft.addressLine1);
      expect(restored.addressLine2, draft.addressLine2);
      expect(restored.city, draft.city);
      expect(restored.provinceOrState, draft.provinceOrState);
      expect(restored.postalCode, draft.postalCode);
      expect(restored.createdAt, DateTime(2026, 1, 1));
    });

    test('isDefault is derived purely from the currentDefaultId parameter, '
        'never read from the document itself', () {
      final data = {
        'fullName': 'X',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        // Even if a legacy/malformed doc somehow had this field, it must
        // never be trusted.
        'isDefault': true,
      };

      final notDefault = addressModelFromFirestore('addr1', data, 'addr2');
      expect(notDefault.isDefault, isFalse);

      final isDefault = addressModelFromFirestore('addr1', data, 'addr1');
      expect(isDefault.isDefault, isTrue);

      final noPointer = addressModelFromFirestore('addr1', data, null);
      expect(noPointer.isDefault, isFalse);
    });

    test('malformed/missing fields fall back to safe defaults rather than '
        'throwing', () {
      expect(
        () => addressModelFromFirestore('addr1', const {}, null),
        returnsNormally,
      );
      final restored = addressModelFromFirestore('addr1', const {
        'fullName': 12345, // wrong type - must not throw
        'addressLine2': true, // wrong type - must fall back to null
      }, null);
      expect(restored.fullName, '');
      expect(restored.addressLine2, isNull);
      expect(restored.city, '');
    });

    test('a pending serverTimestamp (locally null before server ack) falls '
        'back to a display-only "now" approximation rather than throwing', () {
      expect(
        () => addressModelFromFirestore('addr1', const {
          'fullName': 'X',
          'phoneNumber': '1',
          'addressLine1': 'L1',
          'city': 'C',
          'provinceOrState': 'P',
          'postalCode': '0',
          'createdAt': null,
        }, null),
        returnsNormally,
      );
    });

    test('toFirestoreUpdateMap never includes isDefault or createdAt - both '
        'are outside the editable-fields contract', () {
      final address = AddressModel(
        id: 'addr1',
        fullName: 'X',
        phoneNumber: '1',
        addressLine1: 'L1',
        city: 'C',
        provinceOrState: 'P',
        postalCode: '0',
        isDefault: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final map = address.toFirestoreUpdateMap();
      expect(map.containsKey('isDefault'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
      expect(map.containsKey('id'), isFalse);
    });
  });
}
