# Third-party software and redistribution review

## Application code

The repository is intended to be distributed under GNU AGPL-3.0-only. See `LICENSE`. Maintainer must confirm contribution ownership and institutional obligations before public release.

## UltralyticsYOLO

The Xcode project pins the `ultralytics/yolo-ios-app` package through Swift Package Manager, which provides the `UltralyticsYOLO` library. Verify the exact version in `RodentPose.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Ultralytics offers AGPL-3.0 and enterprise licensing. Verify that your complete distribution, modification notices, source availability and any App Store terms can satisfy the licenses before uploading binaries.

License information: https://www.ultralytics.com/license

## Core ML model and data

`MousePose6_960_int8.mlpackage` is bundled. Its filename is not evidence of ownership or redistribution rights. Verify upstream model weights, dataset usage, and any research-only restrictions; document this in `MODEL_PROVENANCE.md`. Do not publish restricted videos or data by default.

## Apple frameworks

Apple SwiftUI, Core ML, PhotosUI, AVFoundation and other system frameworks are governed by their respective Apple developer terms.

## Not legal advice

This checklist identifies open issues, not legal clearance. Publishing a license notice does not automatically clear third-party redistribution rights.
