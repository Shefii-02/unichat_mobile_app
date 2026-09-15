import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';

/// Shared `Lead.stage` presentation — colour tint and display label — used by both the
/// Leads list and the Lead detail page so stage chips look the same everywhere.
const stageTint = <String, Tint>{
  'new': tintPeach,
  'contacted': tintAmber,
  'follow_up': tintAmber,
  'enrolled': tintGreen,
  'lost': tintRed,
};

String stageLabel(String stage) => switch (stage) {
      'new' => 'New',
      'contacted' => 'Contacted',
      'follow_up' => 'Follow-up',
      'enrolled' => 'Won',
      'lost' => 'Lost',
      _ => stage,
    };
