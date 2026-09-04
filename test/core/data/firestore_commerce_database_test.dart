import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/firestore_commerce_database.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';

/// Waits for `notifyListeners()` to go quiet - at least one notify has
/// occurred, and no further notify has arrived for a short grace period.
///
/// Phase 8.9 correction: [FirestoreCommerceDatabase] now has THREE
/// independent async subscriptions (products, orders, payments), each
/// calling `notifyListeners()` on its own first snapshot arrival. A helper
/// that resolved on the very first notify (as this one originally did) is
/// no longer safe - it could resolve on, say, the orders listener's event
/// while the products listener's own event (what a products-focused
/// assertion actually depends on) has not landed yet, causing a flaky
/// premature assertion. Waiting for the notifier to go quiet is robust
/// regardless of how many independent listeners are backing it.
Future<void> _waitForNotify(
  ChangeNotifier notifier,
  void Function() act, {
  Duration quietPeriod = const Duration(milliseconds: 60),
  Duration timeout = const Duration(seconds: 5),
}) async {
  DateTime? lastNotify;
  void listener() {
    lastNotify = DateTime.now();
  }

  notifier.addListener(listener);
  act();

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final last = lastNotify;
    if (last != null && DateTime.now().difference(last) > quietPeriod) {
      break;
    }
    await Future.delayed(const Duration(milliseconds: 15));
  }
  notifier.removeListener(listener);
}

Future<void> _seedProduct(
  FakeFirebaseFirestore firestore,
  String id, {
  required String publicationStatus,
  required bool isActive,
}) {
  return firestore.collection('products').doc(id).set({
    'sku': 'SKU-$id',
    'title': id,
    'description': '',
    'category': 'furniture',
    'subcategory': '',
    'priceAmount': 1000,
    'stockQuantity': 5,
    'isActive': isActive,
    'showInCatalog': true,
    'publicationStatus': publicationStatus,
    'mainImage': {'path': 'assets/x.png', 'source': 'asset', 'altText': ''},
    'galleryMedia': <Map<String, dynamic>>[],
    'experienceType': 'none',
    'availableColors': <String>[],
    'availableSizes': <String>[],
    'specifications': <Map<String, dynamic>>[],
    'deliveryEstimate': '3-5 days',
    'recommendationRank': 0,
    'popularityScore': 0,
    'addedDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'rating': 4.5,
    'reviewCount': 10,
  });
}

ProductModel _buildProduct({required String id, String? title}) {
  return ProductModel(
    id: id,
    sku: 'SKU-$id',
    title: title ?? 'New Product',
    description: 'desc',
    categoryId: 'furniture',
    categoryKind: ProductCategory.furniture,
    subcategory: 'sub',
    priceAmount: 1000,
    stockQuantity: 5,
    mainImage: const ProductImageRef(path: 'assets/x.png'),
    experienceType: ProductExperienceType.none,
    deliveryEstimate: '3-5 days',
    addedDate: DateTime(2026, 1, 1),
  );
}

/// Writes a raw `orders/{id}` document directly (bypasses application code -
/// `fake_cloud_firestore` does not enforce `firestore.rules` anyway, so this
/// mirrors how a real backfilled/seeded document would look on the wire).
Future<void> _seedOrderDoc(
  FakeFirebaseFirestore firestore,
  String id, {
  required String userId,
  required String paymentId,
  double total = 1000,
  OrderStatus orderStatus = OrderStatus.pending,
  DateTime? orderDate,
}) {
  final date = orderDate ?? DateTime(2026, 1, 1);
  return firestore.collection('orders').doc(id).set({
    'userId': userId,
    'paymentId': paymentId,
    'items': [
      {
        'productId': 'p1',
        'productName': 'Test Product',
        'imagePath': 'assets/test.png',
        'imageSource': 'asset',
        'quantity': 1,
        'selectedSize': null,
        'selectedColor': null,
        'unitPrice': total,
        'lineTotal': total,
      },
    ],
    'orderDate': Timestamp.fromDate(date),
    'subtotal': total,
    'deliveryFee': 0,
    'discount': 0,
    'total': total,
    'paymentMethod': 'stripeCard',
    'paymentStatus': 'paid',
    'orderStatus': orderStatus.name,
    'deliveryAddress': {
      'id': 'a1',
      'label': 'Home',
      'fullName': 'Test User',
      'phoneNumber': '9999999999',
      'addressLine1': '123 Test Street',
      'addressLine2': null,
      'city': 'Test City',
      'provinceOrState': 'Test State',
      'postalCode': '00000',
      'isDefault': true,
    },
    'estimatedDeliveryStart': Timestamp.fromDate(
      date.add(const Duration(days: 7)),
    ),
    'estimatedDeliveryEnd': Timestamp.fromDate(
      date.add(const Duration(days: 14)),
    ),
  });
}

Future<void> _seedPaymentDoc(
  FakeFirebaseFirestore firestore,
  String id, {
  required String userId,
  required String orderId,
  double amount = 1000,
}) {
  return firestore.collection('payments').doc(id).set({
    'userId': userId,
    'orderId': orderId,
    'amount': amount,
    'method': 'stripeCard',
    'status': 'paid',
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
  });
}

void main() {
  group('FirestoreCommerceDatabase', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      await _seedProduct(
        firestore,
        'published-active',
        publicationStatus: 'published',
        isActive: true,
      );
      await _seedProduct(
        firestore,
        'draft-active',
        publicationStatus: 'draft',
        isActive: true,
      );
      await _seedProduct(
        firestore,
        'published-inactive',
        publicationStatus: 'published',
        isActive: false,
      );
    });

    test('a customer session only sees published + active products', () async {
      final authState = AuthSessionState()
        ..setSession(
          AuthResult.success(
            userId: 'u1',
            email: 'c@x.com',
            role: UserRole.customer,
          ),
        );
      final db = FirestoreCommerceDatabase(authState, firestore: firestore);
      await _waitForNotify(db, () {});

      expect(db.products.map((p) => p.id).toList(), ['published-active']);
    });

    test(
      'a superAdmin session sees every product, including drafts/inactive',
      () async {
        final authState = AuthSessionState()
          ..setSession(
            AuthResult.success(
              userId: 'admin1',
              email: 'a@x.com',
              role: UserRole.superAdmin,
            ),
          );
        final db = FirestoreCommerceDatabase(authState, firestore: firestore);
        await _waitForNotify(db, () {});

        expect(db.products.map((p) => p.id).toSet(), {
          'published-active',
          'draft-active',
          'published-inactive',
        });
      },
    );

    test(
      'signed-out at construction -> Customer session established afterward '
      '-> the customer product cache loads (regression: a bare '
      'isSuperAdmin==false comparison cannot tell "signed out" apart from '
      '"signed in as customer", so this transition previously never '
      're-subscribed and left the cache empty for a real customer session)',
      () async {
        final authState = AuthSessionState(); // no session - signed out
        final db = FirestoreCommerceDatabase(authState, firestore: firestore);
        // The signed-out branch clears the cache and notifies synchronously
        // inside the constructor (no Firestore listener is started at all -
        // see _subscribeProducts), so the cache is already empty the
        // instant construction returns; nothing to await here.
        expect(db.products, isEmpty);

        await _waitForNotify(
          db,
          () => authState.setSession(
            AuthResult.success(
              userId: 'u1',
              email: 'c@x.com',
              role: UserRole.customer,
            ),
          ),
        );

        expect(db.products.map((p) => p.id).toList(), ['published-active']);
      },
    );

    test('a role flip from customer to superAdmin re-subscribes and reveals '
        'the full catalog', () async {
      final authState = AuthSessionState()
        ..setSession(
          AuthResult.success(
            userId: 'u1',
            email: 'c@x.com',
            role: UserRole.customer,
          ),
        );
      final db = FirestoreCommerceDatabase(authState, firestore: firestore);
      await _waitForNotify(db, () {});
      expect(db.products.map((p) => p.id).toList(), ['published-active']);

      await _waitForNotify(
        db,
        () => authState.setSession(
          AuthResult.success(
            userId: 'u1',
            email: 'c@x.com',
            role: UserRole.superAdmin,
          ),
        ),
      );

      expect(db.products.length, 3);
    });

    test('getProductById throws for an unknown id', () async {
      final authState = AuthSessionState()
        ..setSession(
          AuthResult.success(
            userId: 'admin1',
            email: 'a@x.com',
            role: UserRole.superAdmin,
          ),
        );
      final db = FirestoreCommerceDatabase(authState, firestore: firestore);
      await _waitForNotify(db, () {});

      expect(() => db.getProductById('does-not-exist'), throwsStateError);
    });

    group('Phase 8.6 product-catalog writes (superAdmin only)', () {
      late AuthSessionState authState;
      late FirestoreCommerceDatabase db;

      setUp(() async {
        authState = AuthSessionState()
          ..setSession(
            AuthResult.success(
              userId: 'admin1',
              email: 'a@x.com',
              role: UserRole.superAdmin,
            ),
          );
        db = FirestoreCommerceDatabase(authState, firestore: firestore);
        await _waitForNotify(db, () {});
      });

      test(
        'addProduct creates a new product visible via the live cache',
        () async {
          final newProduct = _buildProduct(id: 'new-product');

          await _waitForNotify(db, () {
            db.addProduct(newProduct);
          });

          expect(db.products.map((p) => p.id), contains('new-product'));
          expect(db.getProductById('new-product').title, 'New Product');
        },
      );

      test(
        'addProduct to an id that already exists is rejected, so a '
        'title-slug collision can never silently overwrite an existing '
        'product (Firestore is keyed by id, unlike Mock\'s plain List)',
        () async {
          final colliding = _buildProduct(
            id: 'published-active',
            title: 'A Completely Different Product',
          );

          await expectLater(db.addProduct(colliding), throwsStateError);

          // The pre-existing document must be untouched.
          expect(
            db.getProductById('published-active').title,
            'published-active',
          );
        },
      );

      test('updateProduct overwrites the existing document', () async {
        final updated = db
            .getProductById('published-active')
            .copyWith(title: 'Updated Title', priceAmount: 9999);

        await _waitForNotify(db, () {
          db.updateProduct(updated);
        });

        final reloaded = db.getProductById('published-active');
        expect(reloaded.title, 'Updated Title');
        expect(reloaded.priceAmount, 9999);
      });

      test('Phase 8.8b: updateProduct\'s full .set() naturally drops the '
          'legacy "category" field on a pre-migration doc, leaving only the '
          'new categoryId/categoryKind - documents the real behavior '
          '(updateProduct is a full document overwrite, not a merge/narrow '
          'update) rather than claiming Admin writes never touch it', () async {
        // The seeded doc is legacy-shaped: only "category", no
        // categoryId/categoryKind (see _seedProduct).
        final before = await firestore
            .collection('products')
            .doc('published-active')
            .get();
        expect(before.data()!.containsKey('category'), isTrue);
        expect(before.data()!.containsKey('categoryId'), isFalse);

        final updated = db
            .getProductById('published-active')
            .copyWith(title: 'Updated Title');
        await _waitForNotify(db, () {
          db.updateProduct(updated);
        });

        final after = await firestore
            .collection('products')
            .doc('published-active')
            .get();
        expect(after.data()!.containsKey('category'), isFalse);
        expect(after.data()!['categoryId'], 'furniture');
        expect(after.data()!['categoryKind'], 'furniture');
      });

      test('setProductActive touches only isActive', () async {
        await _waitForNotify(db, () {
          db.setProductActive('published-active', false);
        });

        final reloaded = db.getProductById('published-active');
        expect(reloaded.isActive, isFalse);
        expect(reloaded.title, 'published-active');
      });

      test('updateStock sets stockQuantity and stamps lastStockUpdatedAt '
          '(Phase 8.11), leaving every other field untouched', () async {
        final before = db.getProductById('published-active');
        expect(before.lastStockUpdatedAt, isNull);

        await _waitForNotify(db, () {
          db.updateStock('published-active', 42);
        });

        final reloaded = db.getProductById('published-active');
        expect(reloaded.stockQuantity, 42);
        expect(reloaded.title, 'published-active');
        expect(reloaded.lastStockUpdatedAt, isNotNull);

        // The raw doc write is a narrow .update(), not a full overwrite.
        final raw = await firestore
            .collection('products')
            .doc('published-active')
            .get();
        expect(raw.data()!['stockQuantity'], 42);
        expect(raw.data()!['lastStockUpdatedAt'], isA<Timestamp>());
        expect(raw.data()!['title'], 'published-active');
      });

      test(
        'Phase 8.11: updateProduct\'s full .set() preserves an existing '
        'lastStockUpdatedAt (carried on the model) and never erases it',
        () async {
          // Stamp it first via updateStock.
          await _waitForNotify(db, () {
            db.updateStock('published-active', 7);
          });
          final stamped = db
              .getProductById('published-active')
              .lastStockUpdatedAt;
          expect(stamped, isNotNull);

          // A normal Admin product-form edit rebuilds the model but carries the
          // existing timestamp through (see
          // AdminProductFormViewModel._buildModelForSave).
          final edited = db
              .getProductById('published-active')
              .copyWith(title: 'Renamed');
          await _waitForNotify(db, () {
            db.updateProduct(edited);
          });

          final after = db.getProductById('published-active');
          expect(after.title, 'Renamed');
          expect(
            after.lastStockUpdatedAt!.millisecondsSinceEpoch,
            stamped!.millisecondsSinceEpoch,
          );
        },
      );

      test('deleteProduct removes the product from the live cache', () async {
        await _waitForNotify(db, () {
          db.deleteProduct('published-active');
        });

        expect(
          db.products.map((p) => p.id),
          isNot(contains('published-active')),
        );
        expect(() => db.getProductById('published-active'), throwsStateError);
      });
    });

    group('Phase 8.9 - orders/payments', () {
      test('a customer session sees only their own orders/payments; admin '
          'sees every customer\'s', () async {
        await _seedOrderDoc(
          firestore,
          '#TW-alice',
          userId: 'alice',
          paymentId: 'pay-alice',
        );
        await _seedPaymentDoc(
          firestore,
          'pay-alice',
          userId: 'alice',
          orderId: '#TW-alice',
        );
        await _seedOrderDoc(
          firestore,
          '#TW-bob',
          userId: 'bob',
          paymentId: 'pay-bob',
        );
        await _seedPaymentDoc(
          firestore,
          'pay-bob',
          userId: 'bob',
          orderId: '#TW-bob',
        );

        final aliceAuth = AuthSessionState()
          ..setSession(
            AuthResult.success(
              userId: 'alice',
              email: 'alice@x.com',
              role: UserRole.customer,
            ),
          );
        final aliceDb = FirestoreCommerceDatabase(
          aliceAuth,
          firestore: firestore,
        );
        await _waitForNotify(aliceDb, () {});
        expect(aliceDb.orders.map((o) => o.id).toList(), ['#TW-alice']);
        expect(aliceDb.payments.map((p) => p.paymentId).toList(), [
          'pay-alice',
        ]);

        final adminAuth = AuthSessionState()
          ..setSession(
            AuthResult.success(
              userId: 'admin1',
              email: 'a@x.com',
              role: UserRole.superAdmin,
            ),
          );
        final adminDb = FirestoreCommerceDatabase(
          adminAuth,
          firestore: firestore,
        );
        await _waitForNotify(adminDb, () {});
        expect(adminDb.orders.map((o) => o.id).toSet(), {
          '#TW-alice',
          '#TW-bob',
        });
        expect(adminDb.payments.map((p) => p.paymentId).toSet(), {
          'pay-alice',
          'pay-bob',
        });
      });

      // Phase 8.13.6 - Final Security Cutover: `submitOrderWithPayment` (and
      // its `OrderIdCollisionException` / `PaymentIdCollisionException`
      // retryable-collision handling and optimistic-cache upsert) has been
      // removed. Orders and payments are created only by the Cloud Functions
      // now, and `firestore.rules` `orders`/`payments` `create` is `if false`
      // for every client (verified in `firestore-tests/run_rules_tests.mjs`).
      // The read-side subscriptions below are unchanged and still fully
      // covered.

      test('a direct Customer A -> Customer B switch (same role, no '
          'intermediate signed-out state) never leaks A\'s orders/payments '
          'into B\'s cache - _QueryKind alone cannot detect this, only the '
          '(role, uid) identity can', () async {
        await _seedOrderDoc(
          firestore,
          '#TW-alice',
          userId: 'alice',
          paymentId: 'pay-alice',
        );
        await _seedOrderDoc(
          firestore,
          '#TW-bob',
          userId: 'bob',
          paymentId: 'pay-bob',
        );

        final authState = AuthSessionState()
          ..setSession(
            AuthResult.success(
              userId: 'alice',
              email: 'alice@x.com',
              role: UserRole.customer,
            ),
          );
        final db = FirestoreCommerceDatabase(authState, firestore: firestore);
        await _waitForNotify(db, () {});
        expect(db.orders.map((o) => o.id).toList(), ['#TW-alice']);

        // Direct switch: setSession -> setSession, no clearSession() in
        // between (real Firebase authStateChanges() has, in some flows,
        // emitted consecutive non-null users with no null in between -
        // this test does not rely on an intermediate signed-out frame
        // ever occurring).
        await _waitForNotify(
          db,
          () => authState.setSession(
            AuthResult.success(
              userId: 'bob',
              email: 'bob@x.com',
              role: UserRole.customer,
            ),
          ),
        );

        expect(db.orders.map((o) => o.id).toList(), ['#TW-bob']);
        expect(db.orders.map((o) => o.id), isNot(contains('#TW-alice')));
      });

      test('a transient orders-listener error preserves the last '
          'successfully-loaded cache instead of clearing to an '
          'indistinguishable-from-empty state', () async {
        await _seedOrderDoc(
          firestore,
          '#TW-alice',
          userId: 'alice',
          paymentId: 'pay-alice',
        );
        final authState = AuthSessionState()
          ..setSession(
            AuthResult.success(
              userId: 'alice',
              email: 'alice@x.com',
              role: UserRole.customer,
            ),
          );
        final db = FirestoreCommerceDatabase(authState, firestore: firestore);
        await _waitForNotify(db, () {});
        expect(db.orders, hasLength(1));
        expect(db.hasOrdersError, isFalse);

        db.debugSimulateOrdersError(db.debugOrdersGeneration);

        expect(db.orders, hasLength(1)); // preserved, not cleared
        expect(db.hasOrdersError, isTrue);
      });

      test('a stale-generation error callback (from a since-superseded '
          'identity) is silently dropped, never resurrecting a previous '
          'identity\'s data', () async {
        final authState = AuthSessionState()
          ..setSession(
            AuthResult.success(
              userId: 'alice',
              email: 'alice@x.com',
              role: UserRole.customer,
            ),
          );
        final db = FirestoreCommerceDatabase(authState, firestore: firestore);
        await _waitForNotify(db, () {});
        final staleGeneration = db.debugOrdersGeneration;

        await _waitForNotify(
          db,
          () => authState.setSession(
            AuthResult.success(
              userId: 'bob',
              email: 'bob@x.com',
              role: UserRole.customer,
            ),
          ),
        );
        expect(db.hasOrdersError, isFalse);

        // An error callback tagged with the OLD (pre-switch) generation
        // must be dropped entirely - it must not flip hasOrdersError for
        // Bob's now-current session.
        db.debugSimulateOrdersError(staleGeneration);
        expect(db.hasOrdersError, isFalse);
      });
    });
  });
}
