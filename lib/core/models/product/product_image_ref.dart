enum ProductImageSource { asset, file, network }

class ProductImageRef {
  final String path;
  final ProductImageSource source;
  final String altText;

  const ProductImageRef({
    required this.path,
    this.source = ProductImageSource.asset,
    this.altText = '',
  });
}
