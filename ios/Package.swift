// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "KMobileProtocol", products: [.library(name: "KMobileProtocol", targets: ["KMobileProtocol"])],
    targets: [.target(name: "KMobileProtocol", path: "KMobile/Protocol",
                      // Apple-framework stream runtimes are compiled by the iOS app target.
                      // Keep the wire/FEC algorithms in this portable test target.
                      exclude: ["StreamAudio.swift", "StreamReceiver.swift", "StreamSession.swift", "StreamVideo.swift"]),
              .testTarget(name: "ProtocolTests", dependencies: ["KMobileProtocol"], path: "ProtocolTests")])
