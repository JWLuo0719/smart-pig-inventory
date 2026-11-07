// Keep native transport types out of the browser build.
export 'socket_failure_stub.dart' if (dart.library.io) 'socket_failure_io.dart';
