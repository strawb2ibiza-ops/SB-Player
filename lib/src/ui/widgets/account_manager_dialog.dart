import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/iptv_profile.dart';
import '../../state/app_controller.dart';

class AccountManagerDialog extends StatelessWidget {
  const AccountManagerDialog({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return AlertDialog(
          title: const Text('IPTV accounts'),
          content: SizedBox(
            width: 540,
            child: controller.profiles.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No saved accounts yet.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: controller.profiles.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final profile = controller.profiles[index];
                      final active = controller.activeProfileId == profile.id;
                      return ListTile(
                        leading: Icon(
                          active
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
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
                        onTap: active || controller.loading
                            ? null
                            : () async {
                                final ok =
                                    await controller.switchProfile(profile.id);
                                if (ok && context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'rename') {
                              await _rename(context, profile);
                            } else if (value == 'remove') {
                              await _remove(context, profile);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: controller.loading
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      unawaited(controller.beginAddAccount());
                    },
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _rename(BuildContext context, IptvProfile profile) async {
    final field = TextEditingController(text: profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename account'),
          content: TextField(
            controller: field,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Account name'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(field.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    field.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await controller.renameProfile(profile.id, name);
    }
  }

  Future<void> _remove(BuildContext context, IptvProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text(
          'Remove “${profile.name}” from SB Player? This does not change '
          'anything with the IPTV provider itself.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeProfile(profile.id);
    }
  }
}
