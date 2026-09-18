// Shared model/helpers for the WA Chat campaign sender — mirrors the recipient/dedupe/CSV/variable
// logic in frontend/src/pages/wa-chat/pages/message-sender/index.tsx so the two stay behaviourally
// identical even though the UI shape differs (mobile page vs. web dropdown panel).

/// One row in the campaign's recipient list — the same shape regardless of which of the five
/// recipient tabs it came from. Mirrors the web's `Recipient` type.
class CampaignRecipient {
  const CampaignRecipient({
    required this.id,
    required this.name,
    required this.phone,
    required this.type,
    required this.category,
  });

  final String id;
  final String name;
  /// A plain MSISDN for a manually-entered/contact number, or a raw WhatsApp id
  /// (`...@c.us` / `...@g.us` / `...@lid`) when sourced from a chat or group — sent to the
  /// backend as-is either way; the server resolves a plain number into a chat id itself.
  final String phone;
  final String type; // personal | group | csv | label | chat
  final String category;

  /// Mirrors `recipientDedupeKey`: an id-shaped phone (contains `@`) compares by the exact
  /// lowercased id, a plain number by digits only — so "628123456789" and "628123456789@c.us"
  /// count as the same recipient.
  String get dedupeKey => phone.contains('@') ? phone.toLowerCase() : phone.replaceAll(RegExp(r'\D'), '');

  Map<String, dynamic> toLogEntry() => {'recipient_name': name, 'phone': phone, 'status': 'pending'};
}

/// Mirrors the web's `PHONE_RE`.
final RegExp campaignPhonePattern = RegExp(r'^\+?[0-9]{7,15}$');

/// De-dupes a list by [CampaignRecipient.dedupeKey], first occurrence wins — mirrors
/// `dedupeRecipients`.
List<CampaignRecipient> dedupeCampaignRecipients(Iterable<CampaignRecipient> list) {
  final seen = <String>{};
  final out = <CampaignRecipient>[];
  for (final r in list) {
    if (seen.add(r.dedupeKey)) out.add(r);
  }
  return out;
}

/// Adds [additions] to [existing], skipping any that dedupe-collide with what's already there or
/// with an earlier addition in the same batch. Returns the merged list.
List<CampaignRecipient> mergeCampaignRecipients(
  List<CampaignRecipient> existing,
  Iterable<CampaignRecipient> additions,
) {
  final keys = existing.map((r) => r.dedupeKey).toSet();
  final merged = [...existing];
  for (final r in additions) {
    if (keys.add(r.dedupeKey)) merged.add(r);
  }
  return merged;
}

class CsvParseResult {
  const CsvParseResult(this.valid, this.invalidCount);
  final List<CampaignRecipient> valid;
  final int invalidCount;
}

/// Mirrors `parseCSV`: columns are `phone,name` (name optional); the first line is treated as a
/// header only when it mentions "phone" or "name" (case-insensitive), otherwise it's data.
CsvParseResult parseCampaignCsv(String text) {
  final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return const CsvParseResult([], 0);
  var start = 0;
  final first = lines.first.toLowerCase();
  if (first.contains('phone') || first.contains('name')) start = 1;
  final valid = <CampaignRecipient>[];
  var invalid = 0;
  for (var i = start; i < lines.length; i++) {
    final cols = lines[i].split(',');
    final rawPhone = cols.isNotEmpty ? cols[0].trim() : '';
    final name = cols.length > 1 ? cols[1].trim() : '';
    final cleaned = rawPhone.replaceAll(RegExp(r'[\s\-()+]'), '');
    if (!campaignPhonePattern.hasMatch(cleaned)) {
      invalid++;
      continue;
    }
    final phone = '+$cleaned';
    valid.add(CampaignRecipient(
      id: 'csv-$phone-$i',
      name: name.isEmpty ? phone : name,
      phone: phone,
      type: 'csv',
      category: 'CSV',
    ));
  }
  return CsvParseResult(valid, invalid);
}

/// Client-side preview only — mirrors `personalizeMessage`, which the server re-implements for the
/// actual send (`ProcessMessageSenderJob.php`). Keep the placeholder set and fallbacks identical to
/// that server-side copy if either ever changes.
String personalizeCampaignPreview(
  String body, {
  required String name,
  required String phone,
  String companyDetails = '',
  String companyNumber = '',
}) {
  final now = DateTime.now();
  final date = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final time =
      '${hour12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
  return body
      .replaceAll('{{name}}', name.isEmpty ? 'Friend' : name)
      .replaceAll('{{phone}}', phone)
      .replaceAll('{{date}}', date)
      .replaceAll('{{time}}', time)
      .replaceAll('{{company_details}}', companyDetails)
      .replaceAll('{{company_number}}', companyNumber);
}

/// One block in a Multi Media message, or the single block a media Template resolves to. `type`
/// is one of text/image/video/audio/document.
class CampaignMediaBlock {
  CampaignMediaBlock({required this.type, this.text, this.mediaUrl, this.caption, this.filename});
  String type;
  String? text;
  String? mediaUrl;
  String? caption;
  String? filename;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (text != null) 'text': text,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (caption != null && caption!.isNotEmpty) 'caption': caption,
        if (filename != null) 'filename': filename,
      };
}
