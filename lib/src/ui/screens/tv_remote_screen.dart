import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/tv_pairing_service.dart';
import '../branding/sb_brand.dart';
import '../widgets/brand_backdrop.dart';

class TvRemoteScreen extends StatefulWidget {
  const TvRemoteScreen({super.key, this.session});

  final TvRemoteSession? session;

  @override
  State<TvRemoteScreen> createState() => _TvRemoteScreenState();
}

class _TvRemoteScreenState extends State<TvRemoteScreen> {
  final _service = TvPairingService();
  TvRemoteSession? _session;
  bool _loading = true;
  String? _error;
  String? _lastCommand;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final session = widget.session ?? await _service.loadRemoteSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _send(TvRemoteCommand command, String label) async {
    final session = _session;
    if (session == null) return;
    setState(() {
      _lastCommand = label;
      _error = null;
    });
    try {
      await _service.sendRemoteCommand(session, command);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _forget() async {
    await _service.forgetRemoteSession();
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TV Remote'),
        actions: [
          if (_session != null)
            IconButton(
              tooltip: 'Forget this TV',
              onPressed: _forget,
              icon: const Icon(Icons.link_off_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _session == null
              ? const _NoTvView()
              : BrandBackdrop(
                  dense: true,
                  child: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.tv_rounded,
                                color: SbBrand.brightBlue,
                                size: 52,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _session!.code.isEmpty
                                    ? 'Linked SB Player TV'
                                    : 'TV ' + _session!.code,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _error ??
                                    (_lastCommand == null
                                        ? 'Use your phone like the TV remote.'
                                        : 'Sent: ' + _lastCommand!),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _error == null
                                      ? SbBrand.textMuted
                                      : Colors.redAccent,
                                ),
                              ),
                              const SizedBox(height: 28),
                              _RemotePad(onSend: _send),
                              const SizedBox(height: 22),
                              Row(
                                children: [
                                  Expanded(
                                    child: _RemoteAction(
                                      icon: Icons.arrow_back_rounded,
                                      label: 'Back',
                                      onPressed: () => _send(
                                        TvRemoteCommand.back,
                                        'Back',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _RemoteAction(
                                      icon: Icons.home_rounded,
                                      label: 'Home',
                                      onPressed: () => _send(
                                        TvRemoteCommand.home,
                                        'Home',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _RemoteAction(
                                      icon: Icons.play_pause_rounded,
                                      label: 'Play / Pause',
                                      onPressed: () => _send(
                                        TvRemoteCommand.playPause,
                                        'Play / Pause',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _RemoteAction(
                                      icon: Icons.refresh_rounded,
                                      label: 'Refresh',
                                      prominent: true,
                                      onPressed: () => _send(
                                        TvRemoteCommand.refresh,
                                        'Refresh',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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

class _RemotePad extends StatelessWidget {
  const _RemotePad({required this.onSend});

  final Future<void> Function(TvRemoteCommand command, String label) onSend;

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    Widget button(
      IconData icon,
      TvRemoteCommand command,
      String label, {
      bool primary = false,
    }) {
      return SizedBox(
        width: size,
        height: size,
        child: primary
            ? FilledButton(
                onPressed: () => onSend(command, label),
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              )
            : IconButton.filledTonal(
                onPressed: () => onSend(command, label),
                iconSize: 36,
                icon: Icon(icon),
              ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: SbBrand.elevated.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: SbBrand.electricBlue.withValues(alpha: .18),
        ),
      ),
      child: Column(
        children: [
          button(Icons.keyboard_arrow_up_rounded, TvRemoteCommand.up, 'Up'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              button(
                Icons.keyboard_arrow_left_rounded,
                TvRemoteCommand.left,
                'Left',
              ),
              const SizedBox(width: 16),
              button(
                Icons.circle,
                TvRemoteCommand.select,
                'OK',
                primary: true,
              ),
              const SizedBox(width: 16),
              button(
                Icons.keyboard_arrow_right_rounded,
                TvRemoteCommand.right,
                'Right',
              ),
            ],
          ),
          const SizedBox(height: 10),
          button(
            Icons.keyboard_arrow_down_rounded,
            TvRemoteCommand.down,
            'Down',
          ),
        ],
      ),
    );
  }
}

class _RemoteAction extends StatelessWidget {
  const _RemoteAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.prominent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    if (prominent) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _NoTvView extends StatelessWidget {
  const _NoTvView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv_off_outlined, size: 54),
            SizedBox(height: 16),
            Text(
              'No linked TV',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            Text(
              'Go to Settings → Link a TV and scan the QR code on your TV first.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
