import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  // ---- 发送侧直读流:UIDocumentPicker(.open) 拿 security-scoped URL,不复制原文件 ----
  private let fileChannelName = "xin.dart.zebra/native_file"
  private var pendingPickResult: FlutterResult?
  private var openHandles: [Int: FileHandle] = [:]
  private var nextHandle: Int = 1
  private var accessedUrls: [URL] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeFileStream") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: fileChannelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    // 屏幕常亮通道:传输期间禁止自动锁屏(isIdleTimerEnabled = false),
    // 防止锁屏后网络挂起导致文件传输停滞(与 Android FLAG_KEEP_SCREEN_ON 对应)。
    let screenChannel = FlutterMethodChannel(
      name: "xin.dart.zebra/screen",
      binaryMessenger: registrar.messenger()
    )
    screenChannel.setMethodCallHandler { call, result in
      guard call.method == "setKeepScreenOn",
            let args = call.arguments as? [String: Any],
            let on = args["on"] as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      // on=true → 禁止自动锁屏(保持清醒);on=false → 恢复系统策略
      UIApplication.shared.isIdleTimerEnabled = !on
      result(true)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickFiles":
      pickFiles(result: result)
    case "openRead":
      guard let args = call.arguments as? [String: Any],
            let uri = args["uri"] as? String,
            let offset = args["offset"] as? Int else {
        result(FlutterError(code: "bad_args", message: "uri/offset required", details: nil))
        return
      }
      openRead(uri: uri, offset: offset, result: result)
    case "readChunk":
      guard let args = call.arguments as? [String: Any],
            let handle = args["handle"] as? Int,
            let count = args["count"] as? Int else {
        result(FlutterError(code: "bad_args", message: "handle/count required", details: nil))
        return
      }
      readChunk(handle: handle, count: count, result: result)
    case "closeRead":
      guard let args = call.arguments as? [String: Any],
            let handle = args["handle"] as? Int else {
        result(FlutterError(code: "bad_args", message: "handle required", details: nil))
        return
      }
      closeRead(handle: handle, result: result)
    case "releaseAll":
      releaseAll(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 打开系统文件选择器(单选,.open 模式保留原文件,不复制进沙盒;仅支持单文件传输)。
  /// 返回 [{uri, name, size}] 列表,空列表表示用户取消。
  private func pickFiles(result: @escaping FlutterResult) {
    guard pendingPickResult == nil else {
      result(FlutterError(code: "busy", message: "picker already open", details: nil))
      return
    }
    pendingPickResult = result
    let picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .open)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    topViewController()?.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    let result = pendingPickResult
    pendingPickResult = nil
    let items: [[String: Any]] = urls.compactMap { url in
      // security-scoped:读取前必须 startAccessing,释放时 stopAccessing
      if url.startAccessingSecurityScopedResource() {
        accessedUrls.append(url)
      }
      guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? Int else {
        return nil
      }
      return [
        "uri": url.absoluteString,
        "name": url.lastPathComponent,
        "size": size,
      ]
    }
    result?(items)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pendingPickResult
    pendingPickResult = nil
    result?([])
  }

  /// 打开 URL 的读取句柄并 seek 到 offset(断点续传),返回句柄。
  private func openRead(uri: String, offset: Int, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self,
            let url = URL(string: uri),
            let handle = try? FileHandle(forReadingFrom: url) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "open_failed", message: "cannot open file", details: nil))
        }
        return
      }
      handle.seek(toOffset: UInt64(max(0, offset)))
      let h = self.nextHandle
      self.nextHandle += 1
      self.openHandles[h] = handle
      DispatchQueue.main.async { result(h) }
    }
  }

  /// 从句柄读取最多 count 字节;EOF 返回空数据。
  private func readChunk(handle: Int, count: Int, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self, let fh = self.openHandles[handle] else {
        DispatchQueue.main.async {
          result(FlutterError(code: "bad_handle", message: "stream not found", details: nil))
        }
        return
      }
      let data = fh.readData(ofLength: max(0, count))
      DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: data)) }
    }
  }

  /// 关闭句柄对应的句柄与 security-scoped 访问。
  private func closeRead(handle: Int, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { result(true) }
        return
      }
      if let fh = self.openHandles.removeValue(forKey: handle) {
        try? fh.close()
      }
      DispatchQueue.main.async { result(true) }
    }
  }

  /// 关闭全部句柄并释放全部 security-scoped 访问(会话清理兜底)。
  private func releaseAll(result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { result(true) }
        return
      }
      for fh in self.openHandles.values { try? fh.close() }
      self.openHandles.removeAll()
      for url in self.accessedUrls { url.stopAccessingSecurityScopedResource() }
      self.accessedUrls.removeAll()
      DispatchQueue.main.async { result(true) }
    }
  }

  private func topViewController() -> UIViewController? {
    var vc = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first?.rootViewController
    while let presented = vc?.presentedViewController {
      vc = presented
    }
    return vc
  }
}
