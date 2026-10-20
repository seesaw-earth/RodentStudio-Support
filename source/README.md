# RodentStudio source code

Native Swift/SwiftUI source for **iPhone / iPad** and **macOS** rodent video-analysis workflows.

## Projects

- iOS/iPadOS: [`iOS/RodentStudio-Mobile-iOS/RodentPose.xcodeproj`](iOS/RodentStudio-Mobile-iOS/RodentPose.xcodeproj) (legacy internal Xcode target name)
- macOS: [`macOS/RodentStudio-0.7.1/RodentStudio.xcodeproj`](macOS/RodentStudio-0.7.1/RodentStudio.xcodeproj)

Each project contains its own AGPL-3.0 license text. Check THIRD_PARTY_NOTICES and MODEL_PROVENANCE files for dependencies and model provenance notes. Signing certificates, provisioning profiles, and private test data are not included. The Xcode projects may retain their public bundle identifier settings.

## Core ML models

All included `.mlpackage` model bundles, including `weight.bin`, are tracked by **Git LFS**. After cloning, run `git lfs pull` if the weights were not fetched automatically. See [MODEL_MANIFEST.md](MODEL_MANIFEST.md) for file hashes and sizes.

The project publisher has approved open publication of the YOLO26-trained Core ML packages. This statement does not independently verify the licenses of upstream pretrained weights or training datasets. Do not redistribute third-party training videos without permission.

## Build

Open the relevant `.xcodeproj` in Xcode, select a personal Apple development team for signing, and build. Source disclosure is not a statement that every checkout has passed an App Store Archive or that every research metric has been independently validated.

The existing GitHub Pages support/privacy website is maintained at the repository root.
