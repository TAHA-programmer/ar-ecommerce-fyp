import 'package:flutter/material.dart';
import '../widgets/info_screen_scaffold.dart';

class RoomArInfoView extends StatelessWidget {
  const RoomArInfoView({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoScreenScaffold(
      title: 'How Room AR Works',
      subtitle:
          'Room AR availability depends on product support and device compatibility.',
      sections: [
        InfoSectionData(
          number: 1,
          title: 'Choose an AR-enabled product',
          body: 'Select supported furniture, rugs, decor, or lighting.',
        ),
        InfoSectionData(
          number: 2,
          title: 'Open Room AR',
          body: 'Tap the Room AR option from Product Details.',
        ),
        InfoSectionData(
          number: 3,
          title: 'Prepare your space',
          body:
              'Move your phone slowly so the device can detect the floor and surrounding environment.',
        ),
        InfoSectionData(
          number: 4,
          title: 'Place the product',
          body: 'Position the virtual product on a suitable detected surface.',
        ),
        InfoSectionData(
          number: 5,
          title: 'Adjust the product',
          body:
              'Move, rotate, and scale the virtual item to preview how it fits in your room.',
        ),
        InfoSectionData(
          number: 6,
          title: 'View before buying',
          body:
              'Use the AR preview to help decide whether the product suits your space before adding it to the cart.',
        ),
      ],
    );
  }
}
