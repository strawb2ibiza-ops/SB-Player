import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../state/app_controller.dart';

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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'SB',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900, letterSpacing: -3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locked ? 'Sign in to your SB TV account' : 'Your TV. Your provider. One player.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    if (!locked) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Xtream')),
                          ButtonSegment(value: true, label: Text('M3U')),
                        ],
                        selected: {_useM3u},
                        onSelectionChanged: (value) => setState(() => _useM3u = value.first),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_useM3u && !locked)
                      TextField(
                        controller: _m3u,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'M3U playlist URL', prefixIcon: Icon(Icons.link)),
                        onSubmitted: (_) => _submit(),
                      )
                    else ...[
                      if (!locked) ...[
                        TextField(
                          controller: _server,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(labelText: 'Server URL', prefixIcon: Icon(Icons.dns_outlined)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _username,
                        decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _hidePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword ? 'Show password' : 'Hide password',
                            onPressed: () => setState(() => _hidePassword = !_hidePassword),
                            icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (controller.error != null) ...[
                      const SizedBox(height: 14),
                      Text(controller.error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: controller.loading ? null : _submit,
                      icon: controller.loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: Text(controller.loading ? 'Connecting…' : 'Sign in'),
                    ),
                    if (locked) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Provider settings are managed by SB and are not editable in this edition.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
