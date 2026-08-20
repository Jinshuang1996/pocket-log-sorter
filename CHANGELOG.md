# Changelog

All notable changes to Pocket Log Sorter are documented here.

## 2.1.0 - 2026-08-20

### Added

- Professional dark workspace UI with a large selected-clip preview and profile-group columns.
- Automatic case-insensitive matching of same-name DJI `.LRF` proxy files.
- Fast thumbnail and duration extraction from LRF, with original-video fallback.
- Optional export of matching LRF files beside each classified source video.
- Per-profile clip counts, selected-file evidence and LRF match indicators.

### Changed

- The import area is now permanently clickable as well as drag-and-drop enabled.
- Sorting actions and output settings are consolidated in the right inspector.

## 2.0.0 - 2026-08-20

### Added

- Native macOS SwiftUI interface with drag-and-drop and clickable file picker.
- Native DJI `djmd` MP4/MOV reader and schema-less protobuf parser.
- Detection for D-Log 2, D-Log, D-Log M, HLG, HDR/PQ and Rec.709.
- Copy and move sorting modes with collision-safe filenames.
- Universal Apple Silicon and Intel builds.
- Custom application icon and DMG packaging.
- Unit fixtures for DJI gamma and record-mode metadata paths.
