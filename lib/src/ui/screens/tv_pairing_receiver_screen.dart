import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/tv_pairing_service.dart';
import '../../state/app_controller.dart';
import '../branding/sb_brand.dart';
import '../widgets/brand_backdrop.dart';

class TvPairingReceiverScreen extends StatefulWidget {
  const TvPairingReceiverScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<TvPairingReceiverScreen> createState() =>
      _TvPairingReceiverScreenState();
}

class _TvPairingReceiverScreenState extends State<TvPairingReceiverScreen> {
  final _service = TvPairingService();
  TvPairingOffer? _offer;
  Timer? _pollTimer;
  bool _busy = true;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    final offer = _offer;
    if (offer != null && !widget.controller.signedIn) {
      unawaited(_service.cancelOffer(offer));
    }
    _service.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _pollTimer?.cancel();
    final oldOffer = _offer;
    if (oldOffer != null) {
      unawaited(_service.cancelOffer(oldOffer));
    }
    setState(() {
      _busy = true;
      _offer = null;
      _status = 'Creating secure pairing…';
      _error = null;
    });

    try {
      final offer = await _service.createOffer();
      if (!mounted) return;
      setState(() {
        _offer = offer;
        _busy = false;
        _status = 'Waiting for your phone…';
      });
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 1800),
        (_) => unawaited(_poll()),
      );
      unawaited(_poll());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst('Exception: ', '');
        _status = null;
      });
    }
  }

  Future<void> _poll() async {
    final offer = _offer;
    if (offer == null || _busy) return;
    _busy = true;
    try {
      final account = await _service.pollOffer(offer);
      if (account == null) return;
      if (!mounted) return;
      setState(() => _status = 'Phone approved. Signing in…');

      final signedIn = await widget.controller.signInXtream(
        serverUrl: account.serverUrl,
        username: account.username ?? '',
        password: account.password ?? '',
      );
      if (!signedIn) {
        throw Exception(
          widget.controller.error ?? 'The linked account could not sign in.',
        );
      }

      await _service.consumeOffer(offer);
      _pollTimer?.cancel();
      _pollTimer = null;
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      _pollTimer?.cancel();
      _pollTimer = null;
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _status = null;
      });
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    return Scaffold(
      body: BrandBackdrop(
        dense: true,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Padding(
                padding: const EdgeInsets.all(42),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Sign in with your phone',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Open SB Player on your phone, go to Settings → Link a TV, then scan this code.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SbBrand.textMuted,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: 390,
                      height: 390,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: offer == null
                          ? const Center(
                              child: CircularProgressIndicator(),
                            )
                          : SvgPicture.string(
                              offer.qrSvg,
                              fit: BoxFit.contain,
                            ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'TV CODE',
                      style: TextStyle(
                        color: SbBrand.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      offer?.code ?? '--------',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_status != null)
                      Text(
                        _status!,
                        style: const TextStyle(color: SbBrand.brightBlue),
                      ),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        autofocus: true,
                        onPressed: _start,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (_error == null)
                      OutlinedButton.icon(
                        autofocus: offer != null,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel'),
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
