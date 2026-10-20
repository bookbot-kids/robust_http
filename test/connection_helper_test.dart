import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:robust_http/connection_helper.dart';

void main() {
  late StreamController<List<ConnectivityResult>> states;
  late StreamController<InternetStatus> internet;
  late ConnectionHelper helper;
  final downloads = Object();
  final other = Object();

  setUp(() {
    states = StreamController.broadcast(sync: true);
    internet = StreamController.broadcast(sync: true);
    helper = ConnectionHelper.forTesting(
      stateChanges: states.stream,
      internetChanges: internet.stream,
    );
  });
  tearDown(() async {
    for (final owner in [null, downloads, other]) {
      helper.clearStateSubscriptions(owner: owner);
      helper.clearInternetSubscriptions(owner: owner);
    }
    await states.close();
    await internet.close();
  });

  for (final cancelFirst in [true, false]) {
    test(
      'internet listeners remain independent (legacy first: $cancelFirst)',
      () {
        var syncCalls = 0;
        var downloadCalls = 0;
        void sync(bool connected) {
          syncCalls++;
          if (connected) helper.unlistenInternetChanged();
        }

        void download(bool connected) {
          downloadCalls++;
          if (connected) helper.unlistenInternetChanged(owner: downloads);
        }

        if (cancelFirst) {
          helper.listenInternetChanged(sync);
          helper.listenInternetChanged(download, owner: downloads);
        } else {
          helper.listenInternetChanged(download, owner: downloads);
          helper.listenInternetChanged(sync);
        }
        internet.add(InternetStatus.connected);
        expect(syncCalls, 1);
        expect(downloadCalls, 1);
        internet.add(InternetStatus.disconnected);
        expect(syncCalls, 1);
        expect(downloadCalls, 1);
        // Both can register again after cancellation without stale listeners.
        helper.listenInternetChanged(download, owner: downloads);
        internet.add(InternetStatus.connected);
        expect(downloadCalls, 2);
      },
    );
  }

  test('repeated clear only cancels its owner and releases subscriptions', () {
    var calls = 0;
    helper.listenInternetChanged((_) {}, owner: downloads);
    helper.listenInternetChanged((_) => calls++, owner: other);
    helper.clearInternetSubscriptions(owner: downloads);
    helper.clearInternetSubscriptions(owner: downloads);
    helper.clearInternetSubscriptions();
    internet.add(InternetStatus.connected);
    expect(calls, 1);
    helper.clearInternetSubscriptions(owner: other);
    expect(internet.hasListener, isFalse);
  });

  test('state listeners are isolated from sync and other owners', () {
    var calls = 0;
    helper.listenStateChanged((_) => helper.unlistenStateChanged());
    helper.listenStateChanged((connected) {
      expect(connected, isTrue);
      calls++;
    }, owner: downloads);
    states.add([ConnectivityResult.ethernet]);
    states.add([ConnectivityResult.wifi]);
    expect(calls, 2);
    helper.clearStateSubscriptions(owner: downloads);
    expect(states.hasListener, isFalse);
  });

  test('pack network policy accepts Ethernet and mixed Wi-Fi results', () {
    for (final results in [
      [ConnectivityResult.ethernet],
      [ConnectivityResult.wifi],
      [ConnectivityResult.mobile, ConnectivityResult.wifi],
      [ConnectivityResult.vpn, ConnectivityResult.ethernet],
    ]) {
      expect(ConnectionHelper.allowsPackDownloads(results), isTrue);
    }
    for (final results in <List<ConnectivityResult>>[
      [],
      [ConnectivityResult.none],
      [ConnectivityResult.mobile],
      [ConnectivityResult.vpn],
      [ConnectivityResult.bluetooth],
    ]) {
      expect(ConnectionHelper.allowsPackDownloads(results), isFalse);
    }
  });
}
