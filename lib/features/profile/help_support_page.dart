import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/settings/legal_webview_sheet.dart';

const _supportEmail = 'support@teamzo.io';
const _privacyUrl = 'https://teamzo.io/legal/privacy';
const _termsUrl = 'https://teamzo.io/legal/terms';

const _faqs = [
  (
    'I can\'t clock in',
    'Allow location (and camera if a selfie is needed) for the app, switch on GPS, and make sure you are inside the office area if your company uses a geo-fence.',
  ),
  (
    'I forgot my App Lock PIN',
    'Log out from Profile and sign in again with your email and password. You can then set a new PIN.',
  ),
  (
    'How do I switch to another device?',
    'Open Profile → Linked devices and sign out the old device, then log in on the new one.',
  ),
  (
    'I am not getting notifications',
    'Open Profile → Settings and allow notifications. Also check that battery saver is not restricting the app.',
  ),
  (
    'How do I change my photo or phone number?',
    'Profile → Personal details. Your email can only be changed by your admin.',
  ),
];

/// Help & support: contact options, quick answers and the legal pages.
class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  Future<void> _mail(BuildContext context) async {
    final ok = await launchUrl(
      Uri(
        scheme: 'mailto',
        path: _supportEmail,
        query: 'subject=Teamzo app support',
      ),
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Write to $_supportEmail')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help and support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.altSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.mail_outline_rounded),
              title: const Text(
                'Email support',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(_supportEmail),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _mail(context),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 20, 0, 8),
            child: Text('Quick answers', style: TextStyle(fontSize: 12)),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.altSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final f in _faqs)
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(f.$1, style: const TextStyle(fontSize: 13.5)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.$2,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 20, 0, 8),
            child: Text('Legal', style: TextStyle(fontSize: 12)),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.altSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text(
                    'Privacy Policy',
                    style: TextStyle(fontSize: 14),
                  ),
                  onTap:
                      () => showLegalSheet(
                        context,
                        title: 'Privacy Policy',
                        url: _privacyUrl,
                      ),
                ),
                ListTile(
                  leading: const Icon(Icons.gavel_rounded),
                  title: const Text(
                    'Terms of Service',
                    style: TextStyle(fontSize: 14),
                  ),
                  onTap:
                      () => showLegalSheet(
                        context,
                        title: 'Terms of Service',
                        url: _termsUrl,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
