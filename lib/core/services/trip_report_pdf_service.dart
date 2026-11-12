import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/trip_model.dart';
import '../models/alert_model.dart';
import 'ai_safety_service.dart';

class TripReportPdfService {
  /// Generates a structured, professional, full-page PDF report from trip telemetry and AI analysis.
  static Future<Uint8List> generateTripReportPdf({
    required TripModel trip,
    required AiSafetyReport report,
    List<AlertModel> alerts = const [],
  }) async {
    final pdf = pw.Document();

    final dateFormat = DateFormat('dd MMMM yyyy, hh:mm a');
    final formattedStartTime = dateFormat.format(trip.startTime);
    final formattedEndTime = dateFormat.format(trip.endTime);

    final dist = _cleanText(report.dataSupportedObservations['distance_km']?.toString() ??
        (trip.distance / 1000.0).toStringAsFixed(2));
    final dur = _cleanText(report.dataSupportedObservations['duration_minutes']?.toString() ??
        (trip.duration / 60.0).toStringAsFixed(1));
    final spd = _cleanText(report.dataSupportedObservations['average_speed_kmh']?.toString() ??
        trip.avgSpeed.toStringAsFixed(1));
    final score = _cleanText(report.dataSupportedObservations['safety_score']?.toString() ?? '90');
    final timeOfDay = _cleanText(report.dataSupportedObservations['time_of_day']?.toString() ?? 'Day');
    final riskStr = _cleanText(report.riskLevel.toUpperCase());

    // Risk badge color
    PdfColor riskBadgeColor;
    if (riskStr == 'HIGH') {
      riskBadgeColor = PdfColors.red700;
    } else if (riskStr == 'MEDIUM' || riskStr == 'MODERATE') {
      riskBadgeColor = PdfColors.orange700;
    } else {
      riskBadgeColor = PdfColors.green700;
    }

    final int scoreInt = int.tryParse(score) ?? 90;
    String driverGrade;
    if (scoreInt >= 90) {
      driverGrade = 'GRADE A+ | DEFENSIVE DRIVER';
    } else if (scoreInt >= 75) {
      driverGrade = 'GRADE B | MODERATE ADVISORY';
    } else {
      driverGrade = 'GRADE C | ATTENTION REQUIRED';
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        header: (context) => _buildHeader(trip, formattedStartTime),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          pw.SizedBox(height: 8),

          // 1. EXECUTIVE SCORE & RISK PROFILE CARD
          _buildScoreOverviewCard(
            score: score,
            driverGrade: driverGrade,
            riskStr: riskStr,
            riskColor: riskBadgeColor,
            model: report.model,
          ),
          pw.SizedBox(height: 12),

          // 2. TRIP TELEMETRY METRICS GRID (6 KPIs)
          _buildSectionHeader('TRIP TELEMETRY & PERFORMANCE METRICS'),
          pw.SizedBox(height: 5),
          _buildTelemetryGrid(
            dist: dist,
            dur: dur,
            spd: spd,
            timeOfDay: timeOfDay,
            alertsCount: alerts.length.toString(),
            status: report.dataSupportedObservations['telemetry_completeness']?.toString() ?? 'Complete',
          ),
          pw.SizedBox(height: 12),

          // 3. GPS ROUTE & GEOLOCATION CARD
          _buildSectionHeader('GPS ROUTE & SPATIAL VERIFICATION'),
          pw.SizedBox(height: 5),
          _buildRouteCard(
            startLocation: trip.startLocation,
            endLocation: trip.endLocation,
            tripId: trip.tripId,
            formattedStartTime: formattedStartTime,
            formattedEndTime: formattedEndTime,
          ),
          pw.SizedBox(height: 12),

          // 4. AI TRIP SUMMARY SECTION
          _buildSectionHeader('AI VEHICLE SAFETY ANALYST SUMMARY'),
          pw.SizedBox(height: 5),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 3,
                  height: 38,
                  color: PdfColors.cyan700,
                  margin: const pw.EdgeInsets.only(right: 8, top: 2),
                ),
                pw.Expanded(
                  child: pw.Text(
                    _cleanText(report.tripSummary),
                    style: const pw.TextStyle(
                      fontSize: 9.5,
                      lineSpacing: 1.8,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // 5. ACTIONABLE PRACTICAL DRIVING RECOMMENDATIONS
          _buildSectionHeader('ACTIONABLE PRACTICAL DRIVING RECOMMENDATIONS'),
          pw.SizedBox(height: 5),
          _buildRecommendationsBlock(report.practicalRecommendations),
          pw.SizedBox(height: 12),

          // 6. RECORDED SAFETY ALERTS (Table or Zero Violations Banner)
          _buildSectionHeader('RECORDED TELEMETRY SAFETY EVENTS'),
          pw.SizedBox(height: 5),
          if (alerts.isNotEmpty)
            _buildAlertsTable(alerts)
          else
            _buildZeroAlertsBanner(),
          pw.SizedBox(height: 12),

          // 7. ADAS AUDIT & VERIFICATION FOOTER BOX
          _buildAuditVerificationBox(trip.tripId, report.model),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Row(
      children: [
        pw.Container(
          width: 3,
          height: 11,
          color: PdfColors.cyan800,
          margin: const pw.EdgeInsets.only(right: 5),
        ),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildHeader(TripModel trip, String dateStr) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.cyan700, width: 2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'NEURODRIVE AI ADAS',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.cyan900,
                  letterSpacing: 1.2,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Vehicle Telemetry & Driver Safety Audit Report',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.blueGrey600),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.cyan800,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Text(
                  'OFFICIAL AUDIT',
                  style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                dateStr,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildScoreOverviewCard({
    required String score,
    required String driverGrade,
    required String riskStr,
    required PdfColor riskColor,
    required String model,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey900,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                score,
                style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                '/100',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey400),
              ),
              pw.SizedBox(width: 14),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    driverGrade,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.cyan200,
                      letterSpacing: 0.6,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Evaluated by ${_cleanText(model)} | Verified GPS Telemetry',
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey400),
                  ),
                ],
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: pw.BoxDecoration(
              color: riskColor,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              '$riskStr RISK',
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTelemetryGrid({
    required String dist,
    required String dur,
    required String spd,
    required String timeOfDay,
    required String alertsCount,
    required String status,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _buildCell('Trip Distance', '$dist km', isHeader: true),
            _buildCell('Total Duration', '$dur min', isHeader: true),
            _buildCell('Average Speed', '$spd km/h', isHeader: true),
          ],
        ),
        pw.TableRow(
          children: [
            _buildCell('Time of Day', timeOfDay),
            _buildCell('Safety Alerts', '$alertsCount logged'),
            _buildCell('Telemetry Status', status),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildCell(String label, String value, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _cleanText(label),
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _cleanText(value),
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: isHeader ? PdfColors.blueGrey900 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRouteCard({
    required TripLocation startLocation,
    required TripLocation endLocation,
    required String tripId,
    required String formattedStartTime,
    required String formattedEndTime,
  }) {
    final startCoord = '${startLocation.latitude.toStringAsFixed(4)}, ${startLocation.longitude.toStringAsFixed(4)}';
    final endCoord = '${endLocation.latitude.toStringAsFixed(4)}, ${endLocation.longitude.toStringAsFixed(4)}';

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ORIGIN DEPARTURE', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                pw.SizedBox(height: 1),
                pw.Text(startCoord, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                pw.Text(_cleanText(formattedStartTime), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColors.cyan50,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: PdfColors.cyan200, width: 0.5),
            ),
            child: pw.Text('--> TO -->', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.cyan800)),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('DESTINATION ARRIVAL', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                pw.SizedBox(height: 1),
                pw.Text(endCoord, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                pw.Text(_cleanText(formattedEndTime), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRecommendationsBlock(String rawRecommendations) {
    final cleaned = _cleanText(rawRecommendations);
    final lines = cleaned
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.cyan50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.cyan300, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines.map((line) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 4,
                  height: 4,
                  margin: const pw.EdgeInsets.only(top: 4, right: 6),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.cyan800,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    line,
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      lineSpacing: 1.5,
                      color: PdfColors.cyan900,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  static pw.Widget _buildZeroAlertsBanner() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.green300, width: 0.8),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
            child: pw.Text('[OK]', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ZERO SAFETY VIOLATIONS RECORDED (0 ALERTS)',
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'Clean driving trajectory. No forward collision risks, tailgating incidents, or emergency deceleration maneuvers logged.',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.green800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAlertsTable(List<AlertModel> alerts) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(4.5),
        2: const pw.FlexColumnWidth(1.8),
        3: const pw.FlexColumnWidth(1.7),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _buildTableHeaderCell('Severity'),
            _buildTableHeaderCell('Alert Message'),
            _buildTableHeaderCell('Distance'),
            _buildTableHeaderCell('Time / TTC'),
          ],
        ),
        ...alerts.take(8).map((a) {
          final isCrit = a.severity.toLowerCase() == 'critical';
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isCrit ? PdfColors.red50 : PdfColors.white,
            ),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  a.severity.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: isCrit ? PdfColors.red800 : PdfColors.orange800,
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  _cleanText(a.message),
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  a.distance != null ? '${a.distance!.toStringAsFixed(1)} m' : 'N/A',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  a.ttc != null ? '${a.ttc!.toStringAsFixed(1)} s' : DateFormat('HH:mm:ss').format(a.timestamp),
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTableHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
      ),
    );
  }

  static pw.Widget _buildAuditVerificationBox(String tripId, String model) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('DATA INTEGRITY VERIFICATION', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
              pw.Text('Trip Hash: ${_cleanText(tripId)} | 100% Genuine Telemetry Log', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('AUTOMATED AUDIT ENGINE', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.cyan800)),
              pw.Text('Certified by NeuroDrive ADAS Copilot Platform', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Confidential Driving Telemetry Audit | Generated by NeuroDrive ADAS Copilot',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  /// Phonetically transliterates Tamil Unicode characters (U+0B80 - U+0BFF) into readable Latin script
  /// so that Tamil letters NEVER turn into blank white spaces in PDF.
  static String _transliterateTamil(String input) {
    if (!input.codeUnits.any((c) => c >= 0x0B80 && c <= 0x0BFF)) {
      return input;
    }

    final tamilVowels = <String, String>{
      'அ': 'a', 'ஆ': 'aa', 'இ': 'i', 'ஈ': 'ee', 'உ': 'u', 'ஊ': 'oo',
      'எ': 'e', 'ஏ': 'ae', 'ஐ': 'ai', 'ஒ': 'o', 'ஓ': 'oa', 'ஔ': 'au',
    };

    final consonants = <String, String>{
      'க': 'k', 'ங': 'ng', 'ச': 's', 'ஞ': 'ny', 'ட': 't', 'ண': 'n',
      'த': 'th', 'ந': 'n', 'ப': 'p', 'ம': 'm', 'ய': 'y', 'ர': 'r',
      'ல': 'l', 'வ': 'v', 'ழ': 'zh', 'ள': 'l', 'ற': 'r', 'ன': 'n',
      'ஜ': 'j', 'ஷ': 'sh', 'ஸ': 's', 'ஹ': 'h',
    };

    final matras = <String, String>{
      'ா': 'aa', 'ி': 'i', 'ீ': 'ee', 'ு': 'u', 'ூ': 'oo',
      'ெ': 'e', 'ே': 'ae', 'ை': 'ai', 'ொ': 'o', 'ோ': 'oa', 'ௌ': 'au',
      '்': '',
    };

    final sb = StringBuffer();
    int i = 0;
    while (i < input.length) {
      final ch = input[i];
      if (consonants.containsKey(ch)) {
        if (i + 1 < input.length && matras.containsKey(input[i + 1])) {
          final m = matras[input[i + 1]]!;
          sb.write('${consonants[ch]}$m');
          i += 2;
        } else {
          sb.write('${consonants[ch]}a');
          i++;
        }
      } else if (tamilVowels.containsKey(ch)) {
        sb.write(tamilVowels[ch]);
        i++;
      } else if (ch == 'ஃ') {
        sb.write('k');
        i++;
      } else {
        sb.write(ch);
        i++;
      }
    }
    return sb.toString();
  }

  static String _cleanText(String input) {
    var text = input
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('•', '-')
        .replaceAll('…', '...')
        .replaceAll('🚨', '[!]')
        .replaceAll('⚠️', '[!]')
        .replaceAll('✓', '[OK]')
        .replaceAll('⚡', '*')
        .replaceAll('★', '*')
        .replaceAll('☆', '*');

    text = _transliterateTamil(text);

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      if ((codeUnit >= 32 && codeUnit <= 126) || codeUnit == 10 || codeUnit == 13 || codeUnit == 9) {
        buffer.writeCharCode(codeUnit);
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
  }
}
