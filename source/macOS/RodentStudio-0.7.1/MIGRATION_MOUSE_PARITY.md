# Remaining mouse adjustment parity work

The following iOS behaviors were inspected but are **not yet functionally equivalent** in the macOS prototype:

| iOS original | UI now | Native scientific parity still required |
|---|---|---|
| RodentPose CalibrationCanvas + CalibrationLoupe | Mouse drag & 3x loupe, geometry handles, dimensions | Perspective homography, all per-assay markers and derived zones, live metric recomputation |
| RodentPose ParamsEditor and CommonParamsEditor | Partial basic time and zone controls | Every paradigm-specific threshold/definition, persisted per-video parameter schema, re-analysis |
| RodentPose ReviewPlayerView | Existing raw pose overlay preview | Edit/QC and frame-wise behavioral event correction |
| RodentLimb CalibrationView | Circle/floor/ruler drag + loupe | Pixel-exact calibration, all parameter panels and save-for-all-camera views |
| RodentLimb ReviewPlayer and SessionDetail | Original analyzer Swift code retained | Event relabeling, summary/review/measures UI and provenance |
| RodentFlow ArenaCalibrationView | Editable rectangle/circle/Y/T/EPM and assay markers | Full perspective-safe zone mapping and visual overlay parity |
| RodentFlow ZoneParameterEditor | Editable subset for video assays | Complete threshold editor, post-hoc recalculation from saved classic-centroid samples |
| RodentFlow preview analyzer | Clear unavailable state | Original 10-second preview, classic centroid tracker, mouse QC |

This is intentionally a UI/layout bridge, not the finished native replication of the three iOS apps.
