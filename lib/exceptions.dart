import 'package:intl/intl.dart';

// The text in these exceptions are for public facing modals.
class UnknownException implements Exception {
  String devDescription;
  StackTrace? stackTrace;
  UnknownException(this.devDescription, {this.stackTrace});
  String toString() => devDescription.isNotEmpty == true
      ? 'Error $devDescription, stackTrace: ${stackTrace?.toString()}'
      : Intl.message("We're unsure what happened, but we're looking into it.",
          name: 'unknownException');
}

class ConnectivityException implements Exception {
  final String? message;
  final bool hasConnectionStatus;

  ConnectivityException(this.message, {this.hasConnectionStatus = false});

  String toString() =>
      message ??
      Intl.message('You are not connected to the internet at this time.',
          name: 'notConnected');
}

class RetryFailureException implements Exception {
  String toString() => Intl.message(
      'There is a problem with the internet connection, please retry later.',
      name: 'retryFailure');
}

class UnexpectedResponseException implements Exception {
  String url;
  int statusCode;
  String errorMessage;
  dynamic data;
  StackTrace? stackTrace;
  String requestDetails;

  UnexpectedResponseException(
    this.url,
    this.statusCode,
    this.errorMessage, {
    this.data,
    this.stackTrace,
    this.requestDetails = '',
  });
  String toString() =>
      'Request error [$statusCode] at $url, message: $errorMessage, data: $data, \n\n requestDetails: $requestDetails \n stackTrace: ${stackTrace?.toString()}';
}

class SyncDataException implements Exception {
  dynamic response;
  SyncDataException(this.response);
  String toString() => Intl.message(
      'There was an error while syncing data. Please try again later.',
      name: 'syncDataFailure');
}

class NetworkTimeoutException implements Exception {
  String errorMessage;
  NetworkTimeoutException(this.errorMessage);
  String toString() => errorMessage.isNotEmpty
      ? errorMessage
      : Intl.message('The request timed out, please try again later.',
          name: 'networkTimeout');
}
