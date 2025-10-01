# Mapwarper AI Onboarding

## Architecture overview

- Rails 4.2 app on Ruby 2.4 backed by PostgreSQL + PostGIS (`config/database.example.yml`).
- Map storage and processing rely on GDAL/MapServer CLI tools invoked via `Open3`; configure their locations with `gdal_path` in `config/application.yml` (loaded by `config/initializers/application_config.rb`).
- Redis powers WMS/tile caching (`config/environments/development.rb`), and Paperclip writes source/warped imagery under `public/mapimages/` (paths controlled by APP_CONFIG).
- Domain logic leans on custom enums from `lib/enum_fu` (`acts_as_enum`) and widespread auditing/tagging/commenting concerns.

## Core domain map

- `Map` (`app/models/map.rb`): orchestrates uploads, GDAL conversions (`setup_image`, `warp!`, `mask!`), publishes status, and manages derived files.
- `Layer` (`app/models/layer.rb`): groups maps, builds GDAL tileindexes (`create_tileindex`, `set_bounds`), and tracks counts/visibility.
- `Gcp` (`app/models/gcp.rb`): stores control points and feeds error calculations via `ErrorCalculator`.
- `Import` (`app/models/import.rb`): batch CSV ingestion of maps, async via `Spawnling`, writing logs to `log/imports`.
- Roles/permissions (`app/models/role.rb`, `permission.rb`, `user.rb`) drive admin/editor gating; Devise lives under `/u/*` (`config/routes.rb`).

## Geospatial workflow gotchas

- Image uploads convert to compressed GeoTIFFs using `gdal_translate` and `gdaladdo`; ensure `MAX_DIMENSION`/`MAX_ATTACHMENT_SIZE` are set in `config/application.yml` before relying on them.
- Warping requires ≥3 hard GCPs (`gcps.hard`); API/HTML actions guard against concurrent warps by checking `status == :warping`.
- Tile/layer caching clears via `Layer#update_layer`, which deletes Redis patterns and regenerates shapefiles in `db/maptileindex/`.
- Utility helpers for GDAL introspection live in `lib/misc/gdalinfo.rb`; keep CLI paths consistent with test overrides in `test/test_helper.rb`.

## Configuration checklist

- Copy `.example` configs to real ones (`config/application.yml`, `config/database.yml`, `config/secrets.yml`) and set `host`, `email`, OAuth keys, hCaptcha, and import SFTP path.
- After `bundle install`, create databases and enable PostGIS manually: `createdb mapwarper_development` + `psql mapwarper_development -c "create extension postgis;"`.
- Start Redis locally before running dev server to avoid cache adapter errors.
- Tests expect fixture data directories to exist; `test/test_helper.rb` rewires `SRC_MAPS_DIR`, `DST_MAPS_DIR`, and tileindex paths to `test/fixtures/data`.

## Everyday workflows

- Run the app with `bundle exec rails s` (Thin is bundled for production-like runs).
- Execute migrations with `bundle exec rake db:migrate`; watch for long GDAL operations when seed data invokes `Map` callbacks.
- Run the suite through `bundle exec rake test`; WebMock + Mocha are preloaded, and Paperclip uses a temporary path under `test/test_files`.
- API smoke checks: controllers under `app/controllers/api/v1` speak JSON:API via ActiveModelSerializers (`config/initializers/active_serial.rb`). Serializers in `app/serializers` define links expected by clients.

## Patterns to follow

- Keep new enumerations consistent with `acts_as_enum` to preserve serialization and validation helpers.
- When touching geospatial CLI calls, reuse helpers in `Map`/`Layer` or `lib/misc` and respect `GDAL_PATH` joins; avoid shell string interpolation that bypasses existing sanitisation.
- Web UI interactions live in `app/assets/javascripts/*.js` and vendor OpenLayers/iD assets; stick with jQuery patterns already used in `application.js` manifests.
- For maintenance scripts, check `lib/tasks/*.rake` (`warper:layer_updatetileindex`, `warper:map_updatebbox`) before reimplementing batch jobs.
- Consult `README_API.md` for accepted JSON shapes, required auth headers (`X-User-Token`, `X-User-Id`), and pagination semantics when expanding the API.
