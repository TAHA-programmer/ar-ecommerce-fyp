import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_colors.dart';

class ProductDiscoveryVisual extends StatelessWidget {
  const ProductDiscoveryVisual({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Hero takes up mostly full width (small side margins are handled by parent padding)
        final double heroWidth = constraints.maxWidth;
        // Figma reference: 395 x 435 -> ratio is 435 / 395 ≈ 1.10
        final double heroHeight = heroWidth * (435.0 / 395.0);

        return Center(
          child: SizedBox(
            width: heroWidth,
            height: heroHeight,
            child: Stack(
              children: [
                // Top-Left (Pendant)
                _buildRegion(
                  region: MosaicRegion.topLeft,
                  assetPath: AppAssets.onboardingRoomPendant,
                  alignment: const Alignment(0.5, 0.5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                  ),
                ),

                // Top-Right (Sofa)
                _buildRegion(
                  region: MosaicRegion.topRight,
                  assetPath: AppAssets.onboardingRoomSofa,
                  alignment: const Alignment(-0.5, 0.5),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(24),
                  ),
                ),

                // Bottom-Left (Wall Art)
                _buildRegion(
                  region: MosaicRegion.bottomLeft,
                  assetPath: AppAssets.onboardingRoomWallArt,
                  alignment: const Alignment(0.5, -0.5),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                  ),
                ),

                // Bottom-Right (Console)
                _buildRegion(
                  region: MosaicRegion.bottomRight,
                  assetPath: AppAssets.onboardingRoomConsole,
                  alignment: const Alignment(-0.5, -0.5),
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(24),
                  ),
                ),

                // Center (Armchair)
                _buildRegion(
                  region: MosaicRegion.center,
                  assetPath: AppAssets.onboardingRoomArmchair,
                  alignment: Alignment.center,
                  borderRadius: BorderRadius.zero, // Central diamond
                ),

                // Decorative QR Badge (no text, overlapping top-left/center intersection)
                Positioned(
                  left: heroWidth * 0.12,
                  top: heroHeight * 0.22,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRegion({
    required MosaicRegion region,
    required String assetPath,
    required Alignment alignment,
    required BorderRadius borderRadius,
  }) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: ClipPath(
          clipper: MosaicClipper(region: region, gapX: 0.008, gapY: 0.007),
          child: Image.asset(
            assetPath,
            fit: BoxFit.cover,
            alignment: alignment,
          ),
        ),
      ),
    );
  }
}

enum MosaicRegion { center, topLeft, topRight, bottomLeft, bottomRight }

class MosaicClipper extends CustomClipper<Path> {
  final MosaicRegion region;
  final double gapX;
  final double gapY;

  // Normalized geometry to create a symmetric large central diamond.
  static const double cL = 0.08;
  static const double cR = 0.92;
  static const double cT = 0.12;
  static const double cB = 0.88;

  MosaicClipper({required this.region, this.gapX = 0.008, this.gapY = 0.007});

  @override
  Path getClip(Size size) {
    final path = Path();
    final double w = size.width;
    final double h = size.height;
    final double gX = gapX * w;
    final double gY = gapY * h;

    final double pxL = cL * w;
    final double pxR = cR * w;
    final double pxT = cT * h;
    final double pxB = cB * h;
    final double midX = w / 2;
    final double midY = h / 2;

    switch (region) {
      case MosaicRegion.center:
        path.moveTo(midX, pxT + gY);
        path.lineTo(pxR - gX, midY);
        path.lineTo(midX, pxB - gY);
        path.lineTo(pxL + gX, midY);
        path.close();
        break;
      case MosaicRegion.topLeft:
        path.moveTo(0, 0);
        path.lineTo(midX - gX, 0);
        path.lineTo(midX - gX, pxT);
        path.lineTo(pxL, midY - gY);
        path.lineTo(0, midY - gY);
        path.close();
        break;
      case MosaicRegion.topRight:
        path.moveTo(midX + gX, 0);
        path.lineTo(w, 0);
        path.lineTo(w, midY - gY);
        path.lineTo(pxR, midY - gY);
        path.lineTo(midX + gX, pxT);
        path.close();
        break;
      case MosaicRegion.bottomRight:
        path.moveTo(w, midY + gY);
        path.lineTo(w, h);
        path.lineTo(midX + gX, h);
        path.lineTo(midX + gX, pxB);
        path.lineTo(pxR, midY + gY);
        path.close();
        break;
      case MosaicRegion.bottomLeft:
        path.moveTo(0, midY + gY);
        path.lineTo(pxL, midY + gY);
        path.lineTo(midX - gX, pxB);
        path.lineTo(midX - gX, h);
        path.lineTo(0, h);
        path.close();
        break;
    }
    return path;
  }

  @override
  bool shouldReclip(MosaicClipper oldClipper) =>
      oldClipper.region != region ||
      oldClipper.gapX != gapX ||
      oldClipper.gapY != gapY;
}
