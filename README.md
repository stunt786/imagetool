# PixelTools

Offline image & PDF toolkit built with Flutter (feature-first, Clean-ish architecture).

## Getting Started

Current status: Phase 1 (Foundation) scaffold from `specification.md` — navigation, theme, and file selection pipeline. Processing features (resize/convert/PDF tools) are intentionally stubbed and implemented in later phases.

### Run

- `flutter pub get`
- `flutter run`

### Project layout

- `lib/core/` app infrastructure (router/theme/constants)
- `lib/shared/` shared widgets + services
- `lib/features/` feature-first modules (each tool has its own folder)
