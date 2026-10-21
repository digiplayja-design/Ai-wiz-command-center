import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class KorlixAppInformation extends StatefulWidget {
  const KorlixAppInformation({super.key, this.load});
  final Future<PackageInfo> Function()? load;
  @override
  State<KorlixAppInformation> createState() => _AppInformationState();
}

class _AppInformationState extends State<KorlixAppInformation> {
  late final Future<PackageInfo> _info =
      (widget.load ?? PackageInfo.fromPlatform)();
  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _info,
    builder: (context, snapshot) {
      final info = snapshot.data;
      final label = info == null
          ? (snapshot.hasError
                ? 'Version information unavailable'
                : 'Loading version…')
          : 'Version ${info.version} • Build ${info.buildNumber}';
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline),
        title: const Text('App information'),
        subtitle: Text(label, key: const Key('app-version-build')),
        trailing: info == null
            ? null
            : IconButton(
                tooltip: 'Copy version and build number',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: 'KORLIX AI — $label'),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Version and build copied.'),
                      ),
                    );
                  }
                },
              ),
      );
    },
  );
}
