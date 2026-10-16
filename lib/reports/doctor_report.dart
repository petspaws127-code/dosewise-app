import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/models.dart';
import '../meds/medication_repository.dart';

/// Builds the adherence report PDF shown behind the rewarded opt-in
/// (Stats → "Doctor report"). Pure function of repository data.
class DoctorReport {
  static Future<Uint8List> build({
    required List<Medication> meds,
    required List<MedAdherence> adherence30,
    required int streak,
    required double? weekPercent,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final dateFmt = DateFormat('MM/dd/yyyy');

    final teal = PdfColor.fromInt(0xFF0E7C6B);
    final ink = PdfColor.fromInt(0xFF22312D);
    final muted = PdfColor.fromInt(0xFF6E7B76);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          pw.Text('DoseWise — Adherence Report',
              style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: ink)),
          pw.SizedBox(height: 4),
          pw.Text('Generated ${dateFmt.format(now)} · Last 30 days',
              style: pw.TextStyle(fontSize: 11, color: muted)),
          pw.SizedBox(height: 4),
          pw.Text(
            'This report summarizes doses logged in the DoseWise app. '
            'It is not medical advice. Always follow your doctor\'s instructions.',
            style: pw.TextStyle(fontSize: 10, color: muted),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              _statBox('Current streak', '$streak days', teal),
              pw.SizedBox(width: 12),
              _statBox(
                  'This week',
                  weekPercent == null
                      ? '—'
                      : '${weekPercent.toStringAsFixed(0)}%',
                  teal),
              pw.SizedBox(width: 12),
              _statBox('Medications tracked', '${meds.length}', teal),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('Adherence by medication (30 days)',
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: ink)),
          pw.SizedBox(height: 8),
          if (adherence30.isEmpty)
            pw.Text('No dose history yet.',
                style: pw.TextStyle(fontSize: 11, color: muted))
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Medication', 'Dose', 'Adherence', 'Doses'],
              data: [
                for (final a in adherence30)
                  [
                    a.med.name,
                    a.med.dose,
                    '${a.percent.toStringAsFixed(0)}%',
                    '${a.doses}',
                  ],
              ],
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 11),
              headerDecoration: pw.BoxDecoration(color: teal),
              cellStyle:
                  pw.TextStyle(fontSize: 11, color: ink),
              cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
            ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Bring this report to your next appointment to discuss '
            'your routine with your doctor or pharmacist.',
            style: pw.TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _statBox(String label, String value, PdfColor accent) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: accent, width: 1),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: accent)),
            pw.SizedBox(height: 2),
            pw.Text(label,
                style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
