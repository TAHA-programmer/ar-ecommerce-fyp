import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/app_router.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/core/services/storage_service.dart';
import 'package:twin_ar/features/admin/ar_media_management/viewmodels/admin_ar_model_preview_viewmodel.dart';
import 'package:twin_ar/features/admin/ar_media_management/views/admin_ar_model_preview_view.dart';

void main() {
  Widget host() => MultiProvider(
    providers: [
      ChangeNotifierProvider<CommerceDatabase>(
        create: (_) => MockCommerceDatabase(),
      ),
      Provider<StorageService>(create: (_) => MockStorageService()),
    ],
    child: MaterialApp(
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => Navigator.pushNamed(
                  context,
                  RouteNames.adminArModelPreview,
                  arguments: const AdminArModelPreviewArgs(
                    metadata: ProductArMetadata(
                      storagePath: 'products/x/ar/model-v1.glb',
                      modelVersion: '1',
                      sha256: 'z',
                      widthM: 1,
                      depthM: 1,
                      heightM: 1,
                    ),
                    productTitle: 'X',
                    widthM: 1,
                    depthM: 1,
                    heightM: 1,
                  ),
                ),
                child: const Text('good'),
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(
                  context,
                  RouteNames.adminArModelPreview,
                  arguments: 'not-args',
                ),
                child: const Text('bad'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('adminArModelPreview builds with valid args', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('good'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AdminArModelPreviewView), findsOneWidget);
  });

  testWidgets('adminArModelPreview rejects a malformed argument', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('bad'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminArModelPreviewView), findsNothing);
    expect(find.textContaining('No model to preview'), findsOneWidget);
  });
}
