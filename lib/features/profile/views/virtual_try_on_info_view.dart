import 'package:flutter/material.dart';
import '../widgets/info_screen_scaffold.dart';

class VirtualTryOnInfoView extends StatelessWidget {
  const VirtualTryOnInfoView({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoScreenScaffold(
      title: 'How Virtual Try-On Works',
      subtitle:
          'Virtual Try-On provides a visual preview and may not represent exact physical sizing or fit.',
      sections: [
        InfoSectionData(
          number: 1,
          title: 'Choose a supported clothing item',
          body: 'Look for clothing products that support Virtual Try-On.',
        ),
        InfoSectionData(
          number: 2,
          title: 'Tap Try It On',
          body: 'Open Virtual Try-On from Product Details.',
        ),
        InfoSectionData(
          number: 3,
          title: 'Position yourself',
          body: 'Follow the on-screen positioning guidance.',
        ),
        InfoSectionData(
          number: 4,
          title: 'Select your camera',
          body: 'Choose the front or rear camera where available.',
        ),
        InfoSectionData(
          number: 5,
          title: 'Start Virtual Try-On',
          body:
              'The selected garment is visually overlaid for a virtual preview.',
        ),
        InfoSectionData(
          number: 6,
          title: 'Review the preview',
          body: 'Use the result to help decide whether the style suits you.',
        ),
      ],
    );
  }
}
