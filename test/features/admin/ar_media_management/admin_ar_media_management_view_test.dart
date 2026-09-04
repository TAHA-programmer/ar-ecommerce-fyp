import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/admin/widgets/admin_bottom_navigation.dart';
import 'package:twin_ar/features/admin/widgets/admin_header.dart';
import 'package:twin_ar/features/admin/ar_media_management/viewmodels/ar_media_management_viewmodel.dart';
import 'package:twin_ar/features/admin/ar_media_management/views/admin_ar_media_management_view.dart';
import 'package:twin_ar/features/admin/ar_media_management/widgets/admin_media_product_selector.dart';
import 'package:twin_ar/features/admin/ar_media_management/widgets/admin_room_ar_model_card.dart';
import 'package:twin_ar/features/admin/ar_media_management/widgets/admin_vto_configuration_card.dart';

import 'ar_glb_test_support.dart';

void main() {
  late MockCommerceDatabase database;
  late MockStorageService storage;
  late FakeArModelFilePicker picker;
  late ArMediaManagementViewModel viewModel;
  late Directory tmp;

  setUp(() {
    database = MockCommerceDatabase();
    storage = MockStorageService();
    picker = FakeArModelFilePicker();
    tmp = Directory.systemTemp.createTempSync('ar_media_view_test');
    viewModel = ArMediaManagementViewModel.general(
      database,
      storageService: storage,
      filePicker: picker,
    );
  });

  tearDown(() {
    viewModel.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget buildApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthSessionState>(
          create: (_) => AuthSessionState(),
        ),
        ChangeNotifierProvider<ArMediaManagementViewModel>.value(
          value: viewModel,
        ),
      ],
      child: MaterialApp(
        home: const AdminArMediaManagementView(),
        routes: {
          RouteNames.adminProducts: (_) =>
              const Scaffold(body: Text('Product Management Products Mode')),
        },
      ),
    );
  }

  Widget buildScoped(ArMediaManagementViewModel scopedViewModel) {
    return ChangeNotifierProvider<ArMediaManagementViewModel>.value(
      value: scopedViewModel,
      child: const MaterialApp(home: AdminArMediaManagementView()),
    );
  }

  testWidgets('general mode keeps Admin layout, selector, and clear back', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(AdminHeader), findsOneWidget);
    expect(find.byType(AdminBottomNavigation), findsOneWidget);
    expect(find.byType(AdminMediaProductSelector), findsOneWidget);
    expect(find.byKey(const Key('admin_header_back_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin_header_back_button')));
    await tester.pumpAndSettle();
    expect(find.text('Product Management Products Mode'), findsOneWidget);
  });

  testWidgets('product-scoped mode is a simple single-product sub-screen', (
    tester,
  ) async {
    final scoped = ArMediaManagementViewModel.productScoped(
      database.getProductById('luna-accent-chair'),
      storageService: storage,
      filePicker: picker,
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(buildScoped(scoped));
    await tester.pumpAndSettle();

    expect(find.byType(AdminMediaProductSelector), findsNothing);
    expect(find.byType(AdminHeader), findsNothing);
    expect(find.byKey(const Key('product_scoped_back_button')), findsOneWidget);
    expect(find.text('Configure Room AR'), findsOneWidget);
  });

  testWidgets('Room AR selection shows the production model card only', (
    tester,
  ) async {
    viewModel.selectProduct('luna-accent-chair');
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(AdminRoomArModelCard), findsOneWidget);
    expect(find.byType(AdminVtoConfigurationCard), findsNothing);
    // seeded chair carries a committed renderable model
    expect(find.text('Live · customers can view in AR'), findsOneWidget);
    expect(find.byKey(const Key('room_ar_entry_point_toggle')), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a model-less product shows "no model" and a select button', (
    tester,
  ) async {
    viewModel.selectProduct('velvet-armchair');
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room_ar_select_glb_button')), findsOneWidget);
    expect(find.text('No model uploaded'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('picking a valid GLB stages a candidate with editable dims', (
    tester,
  ) async {
    viewModel.selectProduct('velvet-armchair');
    picker.next = writeBoxGlb(dir: tmp, name: 'armchair.glb');
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room_ar_select_glb_button')));
    await tester.pump();
    await tester.pump();

    expect(vm(tester).stagedCandidate, isNotNull);
    expect(find.text('New model staged · save to upload'), findsOneWidget);
    expect(find.byKey(const Key('room_ar_apply_dimensions')), findsOneWidget);
    expect(find.byKey(const Key('room_ar_discard_candidate')), findsOneWidget);

    await tester.pump(const Duration(seconds: 4)); // drain AppToast timer
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('VTO selection shows only the VTO card (unchanged)', (
    tester,
  ) async {
    viewModel.selectProduct('mens-oxford-shirt');
    await tester.binding.setSurfaceSize(const Size(360, 900));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(AdminVtoConfigurationCard), findsOneWidget);
    expect(find.byType(AdminRoomArModelCard), findsNothing);

    await tester.binding.setSurfaceSize(null);
  });
}

ArMediaManagementViewModel vm(WidgetTester tester) => tester
    .widget<AdminRoomArModelCard>(find.byType(AdminRoomArModelCard))
    .viewModel;
