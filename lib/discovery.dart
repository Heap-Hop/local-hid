import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

/// One discovered firmware instance.
class DiscoveredBoard {
  DiscoveredBoard({
    required this.instance,
    required this.host,
    required this.port,
    this.logPort,
    this.version,
  });

  /// mDNS instance name (e.g. `local-hid-7a4f`).
  final String instance;

  /// Resolved IPv4 address as a string.
  final String host;

  /// HID command UDP port from the SRV record.
  final int port;

  /// Optional log_port TXT field — where remote log datagrams come from.
  final int? logPort;

  /// Protocol version advertised via TXT (currently always "1").
  final String? version;

  @override
  String toString() =>
      'DiscoveredBoard($instance @ $host:$port, log=$logPort, v$version)';
}

/// One-shot mDNS lookup for the `_local-hid._udp` service. Returns every
/// instance that answered within [timeout].
///
/// On iOS this triggers the local-network permission prompt; we already
/// added `NSLocalNetworkUsageDescription` to Info.plist. On Android the
/// `INTERNET` + `ACCESS_WIFI_STATE` permissions cover us.
Future<List<DiscoveredBoard>> discoverBoards({
  Duration timeout = const Duration(seconds: 3),
  String service = '_local-hid._udp.local',
}) async {
  // Use the library's default socket factory — it sets the right
  // `reuseAddress` / `reusePort` flags so we can share port 5353 with the
  // OS mDNSResponder (especially on macOS, where 5353 is always busy).
  final client = MDnsClient();

  final results = <DiscoveredBoard>[];
  try {
    await client.start();
    final stopwatch = Stopwatch()..start();

    await for (final ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(service),
      timeout: timeout,
    )) {
      if (stopwatch.elapsed > timeout) break;
      final instanceName = ptr.domainName;
      SrvResourceRecord? srv;
      await for (final s in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(instanceName),
        timeout: const Duration(seconds: 1),
      )) {
        srv = s;
        break;
      }
      if (srv == null) continue;

      // Resolve the SRV target's IPv4 address.
      String? host;
      await for (final ip in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(srv.target),
        timeout: const Duration(seconds: 1),
      )) {
        host = ip.address.address;
        break;
      }
      if (host == null) continue;

      // Pull TXT (version, log_port).
      String? version;
      int? logPort;
      await for (final txt in client.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(instanceName),
        timeout: const Duration(seconds: 1),
      )) {
        for (final entry in txt.text.split('\n')) {
          final eq = entry.indexOf('=');
          if (eq <= 0) continue;
          final key = entry.substring(0, eq);
          final value = entry.substring(eq + 1);
          if (key == 'version') version = value;
          if (key == 'log_port') logPort = int.tryParse(value);
        }
        break;
      }

      // Strip the trailing service suffix from the instance label so the
      // UI can show "local-hid-7a4f" rather than the full DNS name.
      final shortName = instanceName.split('.').first;
      results.add(DiscoveredBoard(
        instance: shortName,
        host: host,
        port: srv.port,
        logPort: logPort,
        version: version,
      ));
    }
  } finally {
    client.stop();
  }
  return results;
}
