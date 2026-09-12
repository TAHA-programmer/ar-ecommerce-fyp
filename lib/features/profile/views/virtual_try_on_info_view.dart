import 'package:flutter/material.dart';
import '../widgets/info_screen_scaffold.dart';

class VirtualTryOnInfoView extends StatelessWidget {
  const VirtualTryOnInfoView({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoScreenScaffold(
      title: 'How Virtual Try-On Works',
      subtitle:
          "Virtual Try-On uses Google's Gemini AI to generate a visual "
          "preview and does not represent exact physical sizing or fit.",
      sections: [
        InfoSectionData(
          number: 1,
          title: 'Choose a supported clothing item',
          body:
              'Look for clothing products with a "Try It On" button on '
              'Product Details.',
        ),
        InfoSectionData(
          number: 2,
          title: 'Select a colour and size',
          body: 'Pick the colour and size you want to preview.',
        ),
        InfoSectionData(
          number: 3,
          title: 'Give consent',
          body:
              'Confirm the Virtual Try-On consent. This is required every '
              'time, before any photo is sent anywhere.',
        ),
        InfoSectionData(
          number: 4,
          title: 'Take or choose a photo',
          body:
              'Use the rear camera or choose a photo from your gallery. '
              'Follow the on-screen guidance for pose, lighting and '
              'background.',
        ),
        InfoSectionData(
          number: 5,
          title: 'Generate your preview',
          body:
              'Your photo is sent securely to Google Gemini to generate a '
              'preview of you wearing the item. This can take up to a '
              'minute.',
        ),
        InfoSectionData(
          number: 6,
          title: 'Review the preview',
          body:
              'The result is a visual estimate, not an exact fit or sizing '
              'guarantee. Add the item to your cart, try another colour, or '
              'retake your photo.',
        ),
      ],
    );
  }
}
