import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../state/app_controller.dart';
import '../branding/sb_brand.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/desktop_window_controls.dart';
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
    } else {
      await widget.controller.signInXtream(
        serverUrl: widget.controller.config.isLocked ? null : _server.text,
        username: _username.text,
        password: _password.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final locked = controller.config.mode == DistributionMode.sbLocked;

    return Scaffold(
      body: BrandBackdrop(
        dense: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(34, 34, 34, 28),
                  decoration: BoxDecoration(
                    color: SbBrand.elevated.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SbBrand.electricBlue.withValues(alpha: .16),
                        blurRadius: 52,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: SbLogo(
                          symbolSize: 82,
                          showWordmark: true,
                          showTagline: true,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        locked ? 'Welcome back' : 'Add your IPTV provider',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        locked
                            ? 'Sign in with your SB Player account details.'
                            : 'Connect with Xtream Codes or an M3U playlist.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: SbBrand.textMuted,
                            ),
                      ),
                      const SizedBox(height: 26),
                      if (!locked && controller.profiles.isNotEmpty) ...[
                        Text(
                          'Saved accounts',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        for (final profile in controller.profiles)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: SbBrand.panel,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: .09),
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: const CircleAvatar(
                                  backgroundColor: SbBrand.panelBlue,
                                  foregroundColor: SbBrand.brightBlue,
                                  child: Icon(Icons.person_outline),
                                ),
                                title: Text(
                                  profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  profile.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: controller.loading
                                    ? null
                                    : () =>
                                        controller.switchProfile(profile.id),
                              ),
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'ADD ANOTHER',
                                  style: TextStyle(
                                    color: SbBrand.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
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
                        const SizedBox(height: 18),
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
                              prefixIcon: Icon(Icons.dns_outlined),
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
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: SbBrand.liveError.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  SbBrand.liveError.withValues(alpha: .34),
                            ),
                          ),
                          child: Text(
                            controller.error!,
                            style: const TextStyle(
                              color: SbBrand.liveError,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: controller.loading ? null : _submit,
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
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.center,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: SbBrand.panelBlue,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: SbBrand.electricBlue
                                  .withValues(alpha: .28),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            child: Text(
                              locked ? 'SB EDITION' : 'OPEN EDITION',
                              style: const TextStyle(
                                color: SbBrand.brightBlue,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: DesktopWindowControls(),
              ),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 150,
              height: 42,
              child: DragToMoveArea(
                child: SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
