import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/iptv_account.dart';
import '../../models/iptv_profile.dart';
import '../../services/tv_pairing_service.dart';
import '../../state/app_controller.dart';
import '../branding/sb_brand.dart';

class LinkTvScreen extends StatefulWidget {
  const LinkTvScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LinkTvScreen> createState() => _LinkTvScreenState();
}

class _LinkTvScreenState extends State<LinkTvScreen> {
  final _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  final _pairingService = TvPairingService();

  TvPairingRequest? _request;
  bool _busy = false;
  bool _done = false;
  String? _error;
  String? _selectedProfileId;

  List<IptvProfile> get _xtreamProfiles {
    return widget.controller.profiles
        .where((profile) => profile.account.type == AccountType.xtream)
        .toList(growable: false);
  }

  IptvAccount? get _selectedAccount {
    final id = _selectedProfileId;
    if (id != null) {
      for (final profile in _xtreamProfiles) {
        if (profile.id == id) return profile.account;
      }
    }

    final current = widget.controller.account;
    if (current?.type == AccountType.xtream) return current;
    return _xtreamProfiles.isNotEmpty ? _xtreamProfiles.first.account : null;
  }

  @override
  void initState() {
    super.initState();
    final active = widget.controller.activeProfile;
    if (active?.account.type == AccountType.xtream) {
      _selectedProfileId = active!.id;
    } else if (_xtreamProfiles.isNotEmpty) {
      _selectedProfileId = _xtreamProfiles.first.id;
    }
  }

  @override
  void dispose() {
    unawaited(_scannerController.dispose());
    _pairingService.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_request != null || _busy || _done) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue?.isNotEmpty == true) {
        raw = barcode.rawValue;
        break;
      }
    }
    if (raw == null) return;

    try {
      final request = TvPairingRequest.parse(raw);
      await _scannerController.stop();
      if (!mounted) return;
      setState(() {
        _request = request;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _approve() async {
    final request = _request;
    final account = _selectedAccount;
    if (request == null || account == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _pairingService.approve(
        request: request,
        account: account,
      );
      if (!mounted) return;
      setState(() {
        _done = true;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _request = null;
      _error = null;
      _done = false;
    });
    await _scannerController.start();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _xtreamProfiles;
    final account = _selectedAccount;

    return Scaffold(
      appBar: AppBar(title: const Text('Link a TV')),
      body: SafeArea(
        child: _done
            ? _SuccessView(
                onDone: () => Navigator.of(context).pop(),
              )
            : _request == null
                ? Column(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MobileScanner(
                              controller: _scannerController,
                              onDetect: _onDetect,
                            ),
                            IgnorePointer(
                              child: Center(
                                child: Container(
                                  width: 250,
                                  height: 250,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: SbBrand.brightBlue,
                                      width: 4,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                        child: Column(
                          children: [
                            const Text(
                              'Scan the QR code shown by SB Player on your TV.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Your IPTV password is encrypted on this phone before it is sent. The pairing expires after a few minutes.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: SbBrand.textMuted),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(22),
                    children: [
                      const Icon(
                        Icons.tv_rounded,
                        size: 64,
                        color: SbBrand.brightBlue,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Link this TV?',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _request!.code.isEmpty
                            ? 'SB Player TV'
                            : 'TV code: ${_request!.code}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: SbBrand.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (profiles.length > 1) ...[
                        DropdownButtonFormField<String>(
                          value: _selectedProfileId,
                          decoration: const InputDecoration(
                            labelText: 'Account to send',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          items: [
                            for (final profile in profiles)
                              DropdownMenuItem(
                                value: profile.id,
                                child: Text(
                                  '${profile.name} — ${profile.subtitle}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) =>
                                  setState(() => _selectedProfileId = value),
                        ),
                        const SizedBox(height: 18),
                      ] else if (account != null)
                        ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(account.label),
                          subtitle: Text(
                            '${Uri.tryParse(account.serverUrl ?? '')?.host ?? 'Xtream'} • ${account.username ?? ''}',
                          ),
                        ),
                      if (account == null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'No Xtream account is available on this phone. Add an Xtream account first.',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: account == null || _busy ? null : _approve,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.link_rounded),
                        label: Text(_busy ? 'Linking…' : 'Link TV'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy ? null : _scanAgain,
                        child: const Text('Scan a different TV'),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 42,
              backgroundColor: Color(0x2224D97B),
              child: Icon(
                Icons.check_rounded,
                size: 48,
                color: Color(0xFF24D97B),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'TV linked',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            const Text(
              'The TV is receiving the encrypted account details and should sign in automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SbBrand.textMuted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
