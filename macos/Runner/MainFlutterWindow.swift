import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSDraggingSource {
  private var fileDragResult: FlutterResult?
  private var fileDragEvent: NSEvent?

  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown || event.type == .leftMouseDragged {
      fileDragEvent = event
    } else if event.type == .leftMouseUp {
      fileDragEvent = nil
    }
    super.sendEvent(event)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let fileDragRegistrar = flutterViewController.registrar(forPlugin: "FileDrag")
    let fileDragChannel = FlutterMethodChannel(name: "kuraku/file_drag", binaryMessenger: fileDragRegistrar.messenger)
    fileDragChannel.setMethodCallHandler { [weak self] call, result in
      do {
        switch call.method {
        case "drag":
          guard let self = self, self.fileDragResult == nil,
                let paths = call.arguments as? [String], !paths.isEmpty,
                let view = self.contentView, let event = self.fileDragEvent else {
            result("cancel")
            return
          }
          let origin = view.convert(event.locationInWindow, from: nil)
          let items = paths.map { path -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: NSURL(fileURLWithPath: path))
            item.setDraggingFrame(NSRect(origin: origin, size: NSSize(width: 48, height: 48)), contents: NSWorkspace.shared.icon(forFile: path))
            return item
          }
          self.fileDragResult = result
          let session = view.beginDraggingSession(with: items, event: event, source: self)
          session.draggingFormation = .pile
          session.animatesToStartingPositionsOnCancelOrFail = true
        case "bookmark":
          guard let paths = call.arguments as? [String] else {
            result(FlutterError(code: "invalid_paths", message: "Expected file paths", details: nil))
            return
          }
          var bookmarks: [String: FlutterStandardTypedData] = [:]
          for path in paths {
            let data = try URL(fileURLWithPath: path).bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmarks[path] = FlutterStandardTypedData(bytes: data)
          }
          result(bookmarks)
        case "resolve":
          guard let bookmarks = call.arguments as? [String: FlutterStandardTypedData] else {
            result(FlutterError(code: "invalid_bookmarks", message: "Expected file bookmarks", details: nil))
            return
          }
          var paths: [String: String] = [:]
          for (oldPath, data) in bookmarks {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data.data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
              paths[oldPath] = url.path
            }
          }
          result(paths)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "file_drag", message: error.localizedDescription, details: nil))
      }
    }

    super.awakeFromNib()
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return context == .outsideApplication ? [.move, .copy] : []
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    // AppKit consumes mouse-up during the drag; finish Flutter's pointer sequence.
    if let event = NSEvent.mouseEvent(with: .leftMouseUp, location: convertPoint(fromScreen: screenPoint), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
      contentView?.mouseUp(with: event)
    }
    let result = fileDragResult
    fileDragResult = nil
    fileDragEvent = nil
    result?(operation.contains(.move) ? "move" : operation.contains(.copy) ? "copy" : "cancel")
  }
}
