import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/cart_firestore_mapper.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_size.dart';

void main() {
  group('cart_firestore_mapper', () {
    test('round-trips a real cart line through '
        'cartItemToFirestoreCreateMap/cartItemModelFromFirestore', () {
      final map = cartItemToFirestoreCreateMap(
        productId: 'p1',
        quantity: 3,
        selectedColor: ProductColorOption.blue,
        selectedSize: ProductSize.m,
        priceAmountSnapshot: 5000,
      );

      final restored = cartItemModelFromFirestore(map);

      expect(restored.productId, 'p1');
      expect(restored.quantity, 3);
      expect(restored.selectedColor, ProductColorOption.blue);
      expect(restored.selectedSize, ProductSize.m);
    });

    test('null color/size round-trip as null, not a garbage enum value', () {
      final map = cartItemToFirestoreCreateMap(
        productId: 'p1',
        quantity: 1,
        selectedColor: null,
        selectedSize: null,
        priceAmountSnapshot: 0,
      );
      final restored = cartItemModelFromFirestore(map);
      expect(restored.selectedColor, isNull);
      expect(restored.selectedSize, isNull);
    });

    test('an unrecognized color/size name degrades to null, never a crash', () {
      final restored = cartItemModelFromFirestore(const {
        'productId': 'p1',
        'quantity': 1,
        'selectedColor': 'not-a-real-color',
        'selectedSize': 'not-a-real-size',
      });
      expect(restored.selectedColor, isNull);
      expect(restored.selectedSize, isNull);
    });

    test('quantity is clamped to 1..99 on read, even if a malformed/legacy '
        'document stored something outside that range', () {
      final tooHigh = cartItemModelFromFirestore(const {
        'productId': 'p1',
        'quantity': 500,
      });
      expect(tooHigh.quantity, 99);

      final tooLow = cartItemModelFromFirestore(const {
        'productId': 'p1',
        'quantity': -5,
      });
      expect(tooLow.quantity, 1);
    });

    test('malformed/missing fields fall back to safe defaults rather than '
        'throwing', () {
      expect(() => cartItemModelFromFirestore(const {}), returnsNormally);
      final restored = cartItemModelFromFirestore(const {
        'productId': 12345, // wrong type
        'quantity': 'not-a-number',
      });
      expect(restored.productId, '');
      expect(restored.quantity, 1);
    });

    test('cartItemToFirestoreUpdateMap never touches addedAt (immutable '
        'after creation)', () {
      final map = cartItemToFirestoreUpdateMap(quantity: 5);
      expect(map.containsKey('addedAt'), isFalse);
      expect(map['quantity'], 5);
    });

    test('priceAmountSnapshot is omitted from the update map when not '
        'provided, rather than being written as null', () {
      final map = cartItemToFirestoreUpdateMap(quantity: 5);
      expect(map.containsKey('priceAmountSnapshot'), isFalse);
    });

    test('a real Firestore Timestamp for addedAt is round-tripped '
        'correctly via cartTimestampFromData', () {
      final ts = Timestamp.fromDate(DateTime(2026, 3, 1));
      final result = cartTimestampFromData({'addedAt': ts}, 'addedAt');
      expect(result, DateTime(2026, 3, 1));
    });
  });
}
