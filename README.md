# robust_http

A robust http Flutter package base on [dio](https://pub.dev/packages/dio).

## Fetures:

- Support to retry on error
- Localize general error
- Config dynamically
- Print http log messages

## Usage

```
var http = HTTP('https://httpstat.us/',
          {"connectTimeout": 3000, "receiveTimeout": 3000, "logLevel": Log.all});
var response = await http.get('200'); // success response
print(response); // print "200 OK"
```