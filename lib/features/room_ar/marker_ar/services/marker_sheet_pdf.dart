import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the print-ready A4 Marker-AR sheet (ported from
/// `_marker_ar_poc/lib/marker_pdf.dart`).
///
/// The marker's OUTER BLACK SQUARE is drawn at EXACTLY [markerMm] millimetres.
/// The native detector is configured for the same dictionary + id, and its pose
/// solver is told the marker is [markerMm] wide — so if the print is accurate,
/// the AR scale is accurate.
Future<Uint8List> buildMarkerSheetPdf({
  required Uint8List markerPng,
  required double markerMm,
  required String dict,
  required int markerId,
}) async {
  final doc = pw.Document();
  final img = pw.MemoryImage(markerPng);
  final mm = PdfPageFormat.mm;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(12 * 2.83465), // 12 mm
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'TWin AR — Room AR marker sheet',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'PRINT AT 100% / ACTUAL SIZE.  In the print dialog turn OFF '
              '"Fit to page", "Shrink to fit" and "Scale to fit". Use A4 paper.',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),

            // 50 mm calibration line — measure this first with a ruler.
            pw.Row(
              children: [
                pw.Container(
                  width: 50 * mm,
                  height: 1.2,
                  color: PdfColors.black,
                ),
                pw.SizedBox(width: 6),
                pw.Text(
                  'this line must measure exactly 50 mm',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // The marker, at exact physical size, centred.
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Container(
                    width: markerMm * mm,
                    height: markerMm * mm,
                    child: pw.Image(img, fit: pw.BoxFit.fill),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'marker outer black square = ${markerMm.toStringAsFixed(1)} mm  '
                    '(measure edge-to-edge of the black border)',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),

            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              'Dictionary: $dict   ·   Marker ID: $markerId',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'How to use:',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Bullet(
              text:
                  'Print this page. Check the 50 mm line and the marker edge with a ruler.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Bullet(
              text:
                  'Lay the sheet FLAT on the floor (or a table) where you want the furniture. Tape the corners so it does not curl.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Bullet(
              text:
                  'Open Room AR, point the rear camera at the marker from about 0.4 to 2 m.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Bullet(
              text:
                  'Room AR (marker mode) needs the printed marker to stay visible. If it leaves the frame the object pauses until you point back at it.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        );
      },
    ),
  );
  return doc.save();
}
