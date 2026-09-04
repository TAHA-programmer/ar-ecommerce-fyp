import 'package:flutter/material.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/models/product/product_image_ref.dart';
import '../../../../core/services/device_image_picker_service.dart';
import '../../../../core/services/image_picker_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/widgets/product_image_view.dart';

class AdminImagePickerSheet extends StatefulWidget {
  final int maxAllowed;

  /// Optional injection seam for tests - production callers never pass
  /// this, so the sheet always uses the real device picker.
  final ImagePickerService? imagePickerService;

  const AdminImagePickerSheet({
    super.key,
    required this.maxAllowed,
    this.imagePickerService,
  });

  @override
  State<AdminImagePickerSheet> createState() => _AdminImagePickerSheetState();
}

class _AdminImagePickerSheetState extends State<AdminImagePickerSheet> {
  late final ImagePickerService _imagePickerService =
      widget.imagePickerService ?? DeviceImagePickerService();

  final Set<String> _selectedPaths = {};

  /// Device photos picked this session, kept separate from the curated-asset
  /// selection grid below - staged as `ProductImageRef(source: .file)`,
  /// uploaded to Storage only when the product form is actually saved (see
  /// `AdminProductFormViewModel._uploadPendingImagesAndUpdateModel`).
  final List<String> _pickedDevicePaths = [];

  bool _isPicking = false;

  int get _totalSelected => _selectedPaths.length + _pickedDevicePaths.length;

  Future<void> _pickFromDevice() async {
    final remainingSlots = widget.maxAllowed - _totalSelected;
    if (remainingSlots <= 0) {
      AppToast.error(
        context,
        'You can only add up to ${widget.maxAllowed} more images.',
      );
      return;
    }

    setState(() => _isPicking = true);
    try {
      final paths = await _imagePickerService.pickMultipleImagesFromGallery(
        maxImages: remainingSlots,
      );
      if (!mounted) return;
      if (paths.isEmpty) return; // user cancelled - not an error
      setState(() {
        _pickedDevicePaths.addAll(paths.take(remainingSlots));
      });
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  final List<String> _curatedAssets = [
    AppAssets.pdLunaChairMain,
    AppAssets.pdLunaChairView2,
    AppAssets.pdLunaChairView3,
    AppAssets.pdLunaChairView4,
    AppAssets.pdLunaChairView5,
    AppAssets.pdOxfordShirtFront,
    AppAssets.pdOxfordShirtBack,
    AppAssets.pdOxfordShirtFabric,
    AppAssets.pdOxfordShirtCollar,
    AppAssets.bestSellerSofa,
    AppAssets.bestSellerRug,
    AppAssets.bestSellerBlueShirt,
    AppAssets.featuredSofa,
    AppAssets.featuredWomensBlazer,
    AppAssets.newArrivalLampDecor,
    AppAssets.newArrivalArmchair,
    AppAssets.newArrivalJacket,
    AppAssets.newArrivalVases,
    AppAssets.arEnabledBedroom,
    AppAssets.arEnabledConsole,
    AppAssets.arEnabledCoffeeTable,
    AppAssets.vtoWomensDress,
    AppAssets.vtoMensHoodie,
    AppAssets.popularSideTable,
  ];

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        if (_totalSelected >= widget.maxAllowed) {
          AppToast.error(
            context,
            'You can only add up to ${widget.maxAllowed} more images.',
          );
        } else {
          _selectedPaths.add(path);
        }
      }
    });
  }

  void _removeDevicePhoto(String path) {
    setState(() => _pickedDevicePaths.remove(path));
  }

  void _onDone() {
    final refs = <ProductImageRef>[
      ..._selectedPaths.map(
        (p) => ProductImageRef(path: p, source: ProductImageSource.asset),
      ),
      ..._pickedDevicePaths.map(
        (p) => ProductImageRef(path: p, source: ProductImageSource.file),
      ),
    ];
    Navigator.of(context).pop(refs);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Select Product Images',
                      style: AppTypography.title,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isPicking ? null : _pickFromDevice,
                icon: _isPicking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_outlined),
                label: Text(
                  _isPicking ? 'Opening gallery...' : 'Upload from Device',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_pickedDevicePaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pickedDevicePaths.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final path = _pickedDevicePaths[index];
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ProductImageView(
                              imageRef: ProductImageRef(
                                path: path,
                                source: ProductImageSource.file,
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: -6,
                            top: -6,
                            child: GestureDetector(
                              onTap: () => _removeDevicePhoto(path),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Or choose from the catalog',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _curatedAssets.length,
                  itemBuilder: (context, index) {
                    final path = _curatedAssets[index];
                    final isSelected = _selectedPaths.contains(path);

                    return GestureDetector(
                      onTap: () => _toggleSelection(path),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.neutralLight,
                            width: isSelected ? 2 : 1,
                          ),
                          image: DecorationImage(
                            image: AssetImage(path),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: isSelected
                            ? const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.check_circle,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _totalSelected > 0 ? _onDone : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Add $_totalSelected Images'),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
