import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/utils/cart_item_key.dart';

void main() {
  group('cartItemFirestoreKey', () {
    test('the same tuple always produces the same key', () {
      final a = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: 'blue',
        selectedSize: 'm',
      );
      final b = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: 'blue',
        selectedSize: 'm',
      );
      expect(a, b);
    });

    test('different variants produce different keys', () {
      final base = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: 'blue',
        selectedSize: 'm',
      );
      final differentColor = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: 'red',
        selectedSize: 'm',
      );
      final differentSize = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: 'blue',
        selectedSize: 'l',
      );
      final differentProduct = cartItemFirestoreKey(
        productId: 'p2',
        selectedColor: 'blue',
        selectedSize: 'm',
      );
      final keys = {base, differentColor, differentSize, differentProduct};
      expect(keys.length, 4);
    });

    test('every key is a valid Firestore document ID (no slash, bounded '
        'length, hex-only)', () {
      final key = cartItemFirestoreKey(
        productId: 'p1/../weird',
        selectedColor: 'a/b',
        selectedSize: null,
      );
      expect(key.contains('/'), isFalse);
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('slashes cannot create accidental collisions across a naive '
        'delimiter join', () {
      // A naive '${productId}_${color}_${size}' join would collide here:
      // productId 'a_b' + color 'c' vs. productId 'a' + color 'b_c'.
      final first = cartItemFirestoreKey(
        productId: 'a_b',
        selectedColor: 'c',
        selectedSize: null,
      );
      final second = cartItemFirestoreKey(
        productId: 'a',
        selectedColor: 'b_c',
        selectedSize: null,
      );
      expect(first, isNot(second));
    });

    test('null components produce a different key than an empty string '
        'component', () {
      final withNullColor = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: null,
        selectedSize: 'm',
      );
      final withEmptyColor = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: '',
        selectedSize: 'm',
      );
      expect(withNullColor, isNot(withEmptyColor));
    });

    test('Unicode values are handled deterministically and safely', () {
      final a = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: '青い色 🎨',
        selectedSize: 'Größe',
      );
      final b = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: '青い色 🎨',
        selectedSize: 'Größe',
      );
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('long-but-valid values produce a safe, bounded-length key', () {
      final longValue = 'x' * 5000;
      final key = cartItemFirestoreKey(
        productId: longValue,
        selectedColor: longValue,
        selectedSize: longValue,
      );
      expect(key.length, 64);
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('a lone null vs. present-but-null-like value never collides', () {
      final noSizeNoColor = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: null,
        selectedSize: null,
      );
      final colorEqualsNullString = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: 'null',
        selectedSize: null,
      );
      expect(noSizeNoColor, isNot(colorEqualsNullString));
    });
  });
}
