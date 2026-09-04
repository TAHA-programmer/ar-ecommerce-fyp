import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';

class AuthHeader extends StatelessWidget {
  final double height;
  final Widget? centerWidget;

  const AuthHeader({super.key, required this.height, this.centerWidget});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          // Faded background artwork
          Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: Image.asset(
                AppAssets.authHeaderBackground,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),

          // White blending into the body
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: height * 0.4,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.0), Colors.white],
                ),
              ),
            ),
          ),

          // Logo, substantially larger and centered
          Center(
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
              ),
              child:
                  centerWidget ??
                  Image.asset(
                    AppAssets.authLogoMark,
                    width:
                        screenWidth * 0.22, // Sized correctly for just the mark
                    fit: BoxFit.contain,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
