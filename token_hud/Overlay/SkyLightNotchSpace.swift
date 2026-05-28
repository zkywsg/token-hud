import AppKit
import Darwin

@MainActor
final class SkyLightNotchSpace {
    static let shared = SkyLightNotchSpace()

    private typealias MainConnectionIDFunction = @convention(c) () -> Int32
    private typealias SpaceCreateFunction = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevelFunction = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpacesFunction = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsAndRemoveFromSpacesFunction = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    private static let notchSurfaceLevel: Int32 = 2_147_483_647

    private var handle: UnsafeMutableRawPointer?
    private var connection: Int32?
    private(set) var spaceID: Int32?
    private var addWindowsAndRemoveFromSpaces: AddWindowsAndRemoveFromSpacesFunction?

    private(set) var unavailableReason: String?
    private(set) var lastDelegateReturnCode: Int32?

    private init() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else {
            unavailableReason = "dlopen failed: \(Self.lastDynamicLoaderError())"
            return
        }
        self.handle = handle

        guard
            let mainConnectionIDSymbol = dlsym(handle, "SLSMainConnectionID"),
            let spaceCreateSymbol = dlsym(handle, "SLSSpaceCreate"),
            let spaceSetAbsoluteLevelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSpacesSymbol = dlsym(handle, "SLSShowSpaces"),
            let addWindowsSymbol = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            unavailableReason = "missing SkyLight symbols: \(Self.lastDynamicLoaderError())"
            return
        }

        let mainConnectionID = unsafeBitCast(
            mainConnectionIDSymbol,
            to: MainConnectionIDFunction.self
        )
        let spaceCreate = unsafeBitCast(
            spaceCreateSymbol,
            to: SpaceCreateFunction.self
        )
        let spaceSetAbsoluteLevel = unsafeBitCast(
            spaceSetAbsoluteLevelSymbol,
            to: SpaceSetAbsoluteLevelFunction.self
        )
        let showSpaces = unsafeBitCast(
            showSpacesSymbol,
            to: ShowSpacesFunction.self
        )
        addWindowsAndRemoveFromSpaces = unsafeBitCast(
            addWindowsSymbol,
            to: AddWindowsAndRemoveFromSpacesFunction.self
        )

        let connection = mainConnectionID()
        let space = spaceCreate(connection, 1, 0)
        guard space != 0 else {
            unavailableReason = "SLSSpaceCreate returned 0"
            return
        }

        _ = spaceSetAbsoluteLevel(connection, space, Self.notchSurfaceLevel)
        _ = showSpaces(connection, [space] as CFArray)

        self.connection = connection
        self.spaceID = space
        unavailableReason = nil
    }

    var isAvailable: Bool {
        connection != nil &&
        spaceID != nil &&
        addWindowsAndRemoveFromSpaces != nil &&
        unavailableReason == nil
    }

    var diagnosticsDescription: String {
        """
        available=\(isAvailable), \
        reason=\(unavailableReason ?? "none"), \
        connection=\(String(describing: connection)), \
        spaceID=\(String(describing: spaceID)), \
        lastDelegateReturnCode=\(String(describing: lastDelegateReturnCode))
        """
    }

    @discardableResult
    func delegateWindow(_ window: NSWindow) -> Bool {
        guard
            let connection,
            let spaceID,
            let addWindowsAndRemoveFromSpaces
        else {
            return false
        }

        let windows = [window.windowNumber] as CFArray
        let result = addWindowsAndRemoveFromSpaces(connection, spaceID, windows, 7)
        lastDelegateReturnCode = result
        return true
    }

    private static func lastDynamicLoaderError() -> String {
        guard let error = dlerror() else { return "unknown" }
        return String(cString: error)
    }
}

