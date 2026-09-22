enum InputSupport { supported, missingTool, unsupportedPlatform }

class NativeInputImplementation {
  Future<InputSupport> checkSupport() async => InputSupport.unsupportedPlatform;
  Future<void> moveAndClick({required double dx, required double dy, String? click}) async {}
  Future<void> sendKeyPress(String key) async {}
  Future<void> lockWorkstation() async {}
}
