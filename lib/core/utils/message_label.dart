/// A short, readable name for a message kind — used where only a label fits (chat lists, previews) and as the fallback when a message has no
/// text. Never "[unknown]": a kind we don't know is simply a "Message".
String messageTypeLabel(String? type) => switch ((type ?? 'text').toLowerCase()) {
      'image' => '📷 Photo',
      'video' => '🎥 Video',
      'audio' => '🎵 Audio',
      'voice' || 'ptt' => '🎤 Voice message',
      'document' => '📄 Document',
      'sticker' => '🌟 Sticker',
      'location' => '📍 Location',
      'contact' || 'contacts' || 'vcard' || 'multi_vcard' => '👤 Contact',
      'poll' => '📊 Poll',
      'call' => '📞 Call',
      'revoked' => '🚫 This message was deleted',
      'masked' => '🔒 Hidden by WhatsApp for security',
      'reaction' => '😊 Reaction',
      'interactive' || 'button' => '🔘 Interactive message',
      'order' => '🛒 Order',
      'system' => 'ℹ️ System message',
      'text' || 'chat' => '',
      _ => '💬 Message',
    };
