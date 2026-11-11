// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "KMobileProtocol", products: [.library(name: "KMobileProtocol", targets: ["KMobileProtocol"])],
    targets: [.target(name: "KMobileProtocol", path: "KMobile/Protocol"),
              .testTarget(name: "ProtocolTests", dependencies: ["KMobileProtocol"], path: "ProtocolTests")])
