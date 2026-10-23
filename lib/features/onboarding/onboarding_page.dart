import 'package:unichat_mobile_app/core/widgets/teamzo_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.body, this.tint);
  final IconData icon;
  final String title;
  final String body;
  final Color tint;
}

const _slides = <_Slide>[
  _Slide(
    Icons.forum_rounded,
    'One inbox for every chat',
    'WhatsApp, Instagram DMs and your website widget — answered by your team from a single shared inbox.',
    Color(0xFF25D366),
  ),
  _Slide(
    Icons.smart_toy_rounded,
    'AI that qualifies leads 24/7',
    'The agent replies in your tone, pulls from your knowledge base and catalog, and routes hot leads to the right person.',
    Color(0xFF14B8A6),
  ),
  _Slide(
    Icons.ads_click_rounded,
    'Ads, catalog and CRM together',
    'Run Meta & Instagram campaigns, sync leads into the pipeline, and track every conversion in one place.',
    Color(0xFF1877F2),
  ),
];

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  Future<void> _finish() async {
    await LocalStorage.setBool(LocalStorage.kOnboardingSeen, true);
    if (mounted) context.go('/auth');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Top section: carousel of onboarding tabs ──────────
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
                  ),
                  Positioned(
                    top: 8,
                    right: 12,
                    child: TextButton(
                      onPressed: _finish,
                      child: Text('Skip',
                          style: TextStyle(color: context.mutedColor)),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom section: logo, name, get-started button ────
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(_slides.length, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active
                                ? theme.colorScheme.primary
                                : context.lineColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset('assets/logo/teamzo-icon-tight.png', width: 64, height: 64),
                    ),
                    const SizedBox(height: 14),
                    const TeamzoWordmark(size: 34),
                    const SizedBox(height: 4),
                    Text('One team. One app.',
                        style: TextStyle(color: context.mutedColor)),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        if (_page < _slides.length - 1) {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        } else {
                          _finish();
                        }
                      },
                      child: Text(_page < _slides.length - 1
                          ? 'Next'
                          : 'Get started'),
                    ),
                    if (_page == _slides.length - 1) ...[
                      const SizedBox(height: 4),
                    ] else
                      TextButton(
                        onPressed: _finish,
                        child: const Text('Get started now'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: slide.tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 62, color: slide.tint),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: context.mutedColor, fontSize: 14.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}
