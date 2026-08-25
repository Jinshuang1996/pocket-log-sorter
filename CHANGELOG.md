# Changelog

All notable changes to Pocket Log Sorter are documented here.

## 2.8.0 - 2026-08-25

### Added

- The main window can now be resized freely from its edges and corners and supports native macOS full-screen mode.
- Added an in-app full-screen control while retaining the standard macOS green window button.

### Changed

- The workspace now adapts its sidebar, inspector, preview height and header content to compact and large window sizes.
- The sidebar and inspector use independent vertical overflow handling at compact heights.

### Fixed

- The clear-all button now participates in the sidebar content flow instead of being pushed over nearby text at smaller window sizes.

## 2.7.0 - 2026-08-25

### Added

- Finder files and folders can now be dragged into the import panel or anywhere in the application window.
- Video and photo cards can be dragged out as native file URLs to Finder and compatible editing applications.

### Fixed

- Replaced the SwiftUI URL transfer drop handler with explicit `public.file-url` item-provider loading for reliable Finder drag-and-drop on macOS.

## 2.6.0 - 2026-08-25

### Added

- JPG and camera RAW previews now support zoom buttons, percentage display, fit-to-window reset, double-click zoom and trackpad pinch gestures.
- Enlarged still images can be panned horizontally and vertically inside the fixed preview area.

### Fixed

- All format groups remain visible after analysis; empty groups are no longer removed from the lower workspace.

## 2.5.0 - 2026-08-25

### Changed

- Each populated format column now owns its vertical scroll area, so a large group no longer stretches every other column.
- The lower workspace scrolls horizontally between formats while the upper preview and controls remain fixed.
- Format columns use a consistent fixed-height workspace with independent vertical scrolling.

### Fixed

- Removed the long blank area shown below short or empty groups when another format contained many files.

## 2.4.0 - 2026-08-25

### Added

- JPG/JPEG photos can now be selected, dragged or discovered recursively and are exported to `07_JPG`.
- Common camera RAW formats, including DNG, ARW, CR2/CR3, NEF, RAF and RW2, are exported to `08_RAW`.
- Still photos receive local ImageIO thumbnails and use the fixed upper preview area without entering the video player.

### Changed

- Project totals now distinguish videos from photos while selection, donut proportions and move/copy export work across both.
- Import and output guidance now describes video, JPG, RAW and LRF behavior.

## 2.3.0 - 2026-08-20

### Fixed

- `.LRF` files can now be selected directly, dragged into the app or discovered while importing folders.
- Imported LRF proxies are paired with same-name videos but never shown as independent clip cards.
- The player checks whether an LRF is playable and automatically falls back to the source video when needed.

### Changed

- Moving source files is now the default export mode.
- LRF files imported before their matching videos are cached and attached when the videos arrive.

## 2.2.0 - 2026-08-20

### Added

- Built-in AVKit video player with LRF/original-source switching.
- Donut chart showing the count and percentage of every detected color profile.
- Per-clip export checkboxes, select all, deselect all and selected-only export.
- Two-direction scrolling confined to the lower profile-group workspace.

### Fixed

- Thumbnail cards now use strict geometry bounds and no longer overlap.
- Long filenames, profile labels, status text and output paths are truncated safely.
- The import, preview, analysis and export controls remain fixed while browsing large batches.

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
