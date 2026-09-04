import 'dart:io';
import 'package:flutter/material.dart';
import '../models/product/product_image_ref.dart';

class ProductImageView extends StatelessWidget {
  final ProductImageRef imageRef;
  final BoxFit fit;
  final double? width;
  final double? height;

  const ProductImageView({
    super.key,
    required this.imageRef,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    switch (imageRef.source) {
      case ProductImageSource.asset:
        return Image.asset(
          imageRef.path,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: _buildError,
        );
      case ProductImageSource.file:
        return Image.file(
          File(imageRef.path),
          fit: fit,
          width: width,
          height: height,
          errorBuilder: _buildError,
        );
      case ProductImageSource.network:
        return Image.network(
          imageRef.path,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: _buildError,
        );
    }
  }

  Widget _buildError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }
}
