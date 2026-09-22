import 'native_input_stub.dart'
    if (dart.library.ffi) 'native_input_ffi.dart';

export 'native_input_stub.dart' show InputSupport;

class NativeInputService {
  final NativeInputImplementation _impl = NativeInputImplementation();

  Future<InputSupport> checkSupport() => _impl.checkSupport();

  Future<void> moveAndClick({required double dx, required double dy, String? click}) =>
      _impl.moveAndClick(dx: dx, dy: dy, click: click);
}
