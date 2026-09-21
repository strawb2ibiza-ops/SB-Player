import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../state/app_controller.dart';
import '../branding/sb_brand.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/sb_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _m3u = TextEditingController();

  var _useM3u = false;
  var _hidePassword = true;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _m3u.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_useM3u) {
      await widget.controller.signInM3u(_m3u.text);
      return;
    }

    await widget.controller.signInXtream(
      serverUrl: widget.controller.config.isLocked ? null : _server.text,
      username: _username.text,
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final locked = controller.config.mode == DistributionMode.sbLocked;

    return Scaffold(
      body: BrandBackdrop(
        dense: true,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: SbBrand.elevated.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: SbBrand.electricBlue.withValues(alpha: 0.32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            SbBrand.electricBlue.withValues(alpha: 0.16),
                        blurRadius: 42,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.58),
                        blurRadius: 52,
                        offset: const Offset(0, 24),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(38, 34, 38, 38),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: SbLogo(
                            symbolSize: 88,
                            showTagline: true,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: _EditionBadge(
                            label: locked ? 'SB EDITION' : 'OPEN EDITION',
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          locked
                              ? 'Sign in to continue watching'
                              : 'Add your IPTV provider',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          locked
                              ? 'Your provider is already configured. Enter your account details to continue.'
                              : 'Use Xtream Codes or an M3U playlist. Your saved accounts stay securely available on this device.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: SbBrand.textMuted,
                              ),
                        ),
                        const SizedBox(height: 30),
                        if (!locked && controller.profiles.isNotEmpty) ...[
                          Text(
                            'Saved accounts',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          for (final profile in controller.profiles)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _SavedAccountCard(
                                title: profile.name,
                                subtitle: profile.subtitle,
                                enabled: !controller.loading,
                                onTap: () =>
                                    controller.switchProfile(profile.id),
                              ),
                            ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'ADD ANOTHER',
                                    style: TextStyle(
                                      color: SbBrand.textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                          ),
                        ],
                        if (!locked) ...[
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                icon: Icon(Icons.dns_outlined),
                                label: Text('Xtream'),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: Icon(Icons.link),
                                label: Text('M3U'),
                              ),
                            ],
                            selected: {_useM3u},
                            onSelectionChanged: (value) =>
                                setState(() => _useM3u = value.first),
                          ),
                          const SizedBox(height: 22),
                        ],
                        if (_useM3u && !locked)
                          TextField(
                            controller: _m3u,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'M3U playlist URL',
                              prefixIcon: Icon(Icons.link),
                            ),
                            onSubmitted: (_) => _submit(),
                          )
                        else ...[
                          if (!locked) ...[
                            TextField(
                              controller: _server,
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(
                                labelText: 'Provider URL',
                                prefixIcon: Icon(Icons.language),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: _username,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: _hidePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _hidePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ],
                        if (controller.error != null) ...[
                          const SizedBox(height: 14),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: SbBrand.liveError.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color:
                                    SbBrand.liveError.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                controller.error!,
                                style: const TextStyle(
                                  color: Color(0xFFFF8E9E),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed:
                              controller.loading ? null : () => _submit(),
                          icon: controller.loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            controller.loading ? 'Connecting…' : 'Continue',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditionBadge extends StatelessWidget {
  const _EditionBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: SbBrand.horizontalBrandGradient,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: SbBrand.electricBlue.withValues(alpha: 0.24),
            blurRadius: 16,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.25,
          ),
        ),
      ),
    );
  }
}

class _SavedAccountCard extends StatelessWidget {
  const _SavedAccountCard({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SbBrand.panelBlue.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 19,
                backgroundColor: SbBrand.panel,
                child: Icon(
                  Icons.person_outline,
                  color: SbBrand.brightBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: SbBrand.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
