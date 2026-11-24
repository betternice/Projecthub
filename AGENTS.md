This is a Flutter mobile application (Android and iOS). Flutter version is pinned with FVM in `.fvmrc` — always run Flutter through `fvm`.

## Commands

```bash
fvm flutter pub get
fvm flutter run
fvm flutter analyze
fvm flutter test
```

Run analyze and test before declaring any task done.

## Architecture

Clean architecture, feature-first. Each feature under `lib/features/<name>/` has:

- `domain/` — entities, repository interfaces, use cases. Pure Dart, no Flutter, Dio, or storage imports.
- `data/` — remote/local data sources, JSON mapping, repository implementations. Repositories catch `DioException` and throw a `Failure` from `lib/core/error/failures.dart`.
- `presentation/` — Cubits (flutter_bloc), pages, widgets. Cubits depend on use cases only and show `Failure.message` to the user.

Shared code lives in `lib/core/` (DI with get_it, network, utils, widgets). App shell, router (go_router), and theme live in `lib/app/`.

## Rules

- Register new dependencies in `lib/core/di/injection.dart`. Screen-level Cubits are factories so a new sign-in never sees the previous account's state.
- Navigation goes through go_router in `lib/app/router.dart`; route paths are in `lib/app/routes.dart`.
- Do not return mock data or swallow errors when an API fails. Metadata (posters, synopsis) is best-effort; OneDrive and sign-in errors must reach the UI.
- Only clear the saved session when Microsoft rejects the refresh token (`invalid_grant` and similar). Network errors must keep the user signed in.
- User-facing text is Thai.
