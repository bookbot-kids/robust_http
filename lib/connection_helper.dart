import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class ConnectionHelper {
  /// Whether the device has any connection status. By default does not include bluetooth in the check
  static Future<bool> hasConnection({bool includeBluetooth = false}) async {
    final status = await Connectivity().checkConnectivity();
    return status == ConnectivityResult.wifi ||
        status == ConnectivityResult.mobile ||
        status == ConnectivityResult.ethernet ||
        (includeBluetooth && status == ConnectivityResult.bluetooth);
  }

  static Future<bool> hasWifiConnection() async {
    return await Connectivity().checkConnectivity() == ConnectivityResult.wifi;
  }

  static Future<bool> hasMobileConnection() async {
    return await Connectivity().checkConnectivity() ==
        ConnectivityResult.mobile;
  }

  /// Whether the device has any internet connection
  static Future<bool> hasInternetConnection() async {
    return await InternetConnectionChecker().hasConnection;
  }
}
