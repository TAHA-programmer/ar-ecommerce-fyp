import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';

class VirtualTryOnVisual extends StatelessWidget {
  const VirtualTryOnVisual({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  AppAssets.onboardingVirtualTryon,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            // Top-right hanger badge
            Positioned(
              top: constraints.maxHeight * 0.1,
              right: constraints.maxWidth * 0.05,
              child: _buildBadge(Icons.checkroom),
            ),
            // Bottom-left interaction badge
            Positioned(
              bottom: constraints.maxHeight * 0.2,
              left: constraints.maxWidth * 0.05,
              child: _buildBadge(Icons.touch_app),
            ),
            // Center loading ring (over chest)
            Positioned(
              top: constraints.maxHeight * 0.4,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
            // Fit : Great card (lower right)
            Positioned(
              bottom: constraints.maxHeight * 0.1,
              right: constraints.maxWidth * 0.02,
              child: _buildFitCard(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBadge(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFAEC500),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }

  Widget _buildFitCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Fit : Great',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xFFAEC500),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(
              5,
              (index) =>
                  const Icon(Icons.star, color: Color(0xFFAEC500), size: 16),
            ),
          ),
        ],
      ),
    );
  }
}
