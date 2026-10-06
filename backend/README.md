<p align="center"><a href="https://laravel.com" target="_blank"><img src="https://raw.githubusercontent.com/laravel/art/master/logo-lockup/5%20SVG/2%20CMYK/1%20Full%20Color/laravel-logolockup-cmyk-red.svg" width="400" alt="Laravel Logo"></a></p>

<p align="center">
<a href="https://github.com/laravel/framework/actions"><img src="https://github.com/laravel/framework/workflows/tests/badge.svg" alt="Build Status"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/dt/laravel/framework" alt="Total Downloads"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/v/laravel/framework" alt="Latest Stable Version"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/l/laravel/framework" alt="License"></a>
</p>

## About Laravel

Laravel is a web application framework with expressive, elegant syntax. We believe development must be an enjoyable and creative experience to be truly fulfilling. Laravel takes the pain out of development by easing common tasks used in many web projects, such as:

- [Simple, fast routing engine](https://laravel.com/docs/routing).
- [Powerful dependency injection container](https://laravel.com/docs/container).
- Multiple back-ends for [session](https://laravel.com/docs/session) and [cache](https://laravel.com/docs/cache) storage.
- Expressive, intuitive [database ORM](https://laravel.com/docs/eloquent).
- Database agnostic [schema migrations](https://laravel.com/docs/migrations).
- [Robust background job processing](https://laravel.com/docs/queues).
- [Real-time event broadcasting](https://laravel.com/docs/broadcasting).

Laravel is accessible, powerful, and provides tools required for large, robust applications.

## Learning Laravel

Laravel has the most extensive and thorough [documentation](https://laravel.com/docs) and video tutorial library of all modern web application frameworks, making it a breeze to get started with the framework.

In addition, [Laracasts](https://laracasts.com) contains thousands of video tutorials on a range of topics including Laravel, modern PHP, unit testing, and JavaScript. Boost your skills by digging into our comprehensive video library.

You can also watch bite-sized lessons with real-world projects on [Laravel Learn](https://laravel.com/learn), where you will be guided through building a Laravel application from scratch while learning PHP fundamentals.

## Agentic Development

Laravel's predictable structure and conventions make it ideal for AI coding agents like Claude Code, Cursor, and GitHub Copilot. Install [Laravel Boost](https://laravel.com/docs/ai) to supercharge your AI workflow:

```bash
composer require laravel/boost --dev

php artisan boost:install
```

Boost provides your agent 15+ tools and skills that help agents build Laravel applications while following best practices.

## Contributing

Thank you for considering contributing to the Laravel framework! The contribution guide can be found in the [Laravel documentation](https://laravel.com/docs/contributions).

## Code of Conduct

In order to ensure that the Laravel community is welcoming to all, please review and abide by the [Code of Conduct](https://laravel.com/docs/contributions#code-of-conduct).

## Security Vulnerabilities

If you discover a security vulnerability within Laravel, please send an e-mail to Taylor Otwell via [taylor@laravel.com](mailto:taylor@laravel.com). All security vulnerabilities will be promptly addressed.

## License

The Laravel framework is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

## Survey polygons API (GPS boundary -> polygon, attributes, Shapefile)

GPS points recorded while walking a boundary are stored as a closed PostGIS `Polygon`
(`survey_polygons`: geometry, raw track, area, perimeter). The polygon's attribute data
(owner, khasra, crop ...) lives in a separate 1:1 table (`survey_polygon_attributes`), and polygons
can be exported to / imported from an ESRI Shapefile (`.shp` in a zip).

### Setup

```bash
# PostgreSQL with PostGIS (the migration runs CREATE EXTENSION IF NOT EXISTS postgis)
php artisan migrate --path=database/migrations/2026_10_05_100000_create_survey_polygons_table.php \
                    --path=database/migrations/2026_10_05_100100_create_survey_polygon_attributes_table.php

# GDAL is required for Shapefile export/import (ogr2ogr)
sudo apt install gdal-bin        # Debian/Ubuntu
ogr2ogr --version                # check it before using /export/shp or /import/shp
```

If GDAL is not on `PATH` (e.g. Windows + QGIS), set the full paths in `.env`. If another install has
already set `GDAL_DATA` / `PROJ_LIB` globally (PostgreSQL does), point the GDAL process at the right folders:

```
OGR2OGR_BIN="C:/Program Files/QGIS 4.0.0/bin/ogr2ogr.exe"
OGRINFO_BIN="C:/Program Files/QGIS 4.0.0/bin/ogrinfo.exe"
GDAL_DATA_DIR="C:/Program Files/QGIS 4.0.0/apps/gdal/share/gdal"
GDAL_PROJ_DIR="C:/Program Files/QGIS 4.0.0/share/proj"
```

Settings: `config/tracking.php` (GPS accuracy threshold, min points, min area, bulk size) and
`config/survey.php` (attribute fields, Shapefile field aliases, GDAL, upload limits).

### Endpoints

All routes need `Authorization: Bearer <sanctum token>`, are scoped to the signed-in user, and the POST
routes are rate limited. Responses use `{ "success", "message", "data" }`; errors use
`{ "success": false, "message", "errors": {...} }`.

| Method | Path | Notes |
|---|---|---|
| POST | `/api/polygons` | create from points; optional `attributes`. 201 created, 200 if the `uuid` exists, 422 bad/zero-area |
| POST | `/api/polygons/bulk` | offline sync; array of the same objects (or `{"items": [...]}`); per item `created` / `duplicate` / `failed` |
| GET | `/api/polygons` | paginated; `?bbox=minLng,minLat,maxLng,maxLat`, `?village=`, `?has_data=true\|false`, `?per_page=` |
| GET | `/api/polygons/geojson` | FeatureCollection for maps (same filters) |
| GET | `/api/polygons/{uuid}` | GeoJSON Feature: geometry + attributes merged into `properties`, raw `track` included |
| DELETE | `/api/polygons/{uuid}` | soft delete |
| GET | `/api/polygons/{uuid}/attributes` | attribute row (`data: null` if none yet) |
| PUT | `/api/polygons/{uuid}/attributes` | create or update (merge); unknown keys go to `extra` |
| DELETE | `/api/polygons/{uuid}/attributes` | remove the attribute row |
| GET | `/api/polygons/export/shp` | zip of `.shp .shx .dbf .prj .cpg`; `?ids[]=1&ids[]=2`, `?bbox=`, `?village=` |
| POST | `/api/polygons/import/shp` | multipart `file` = zip; returns imported / skipped summary |

`description` (optional, max 500 chars) is the text typed in the app's "Start route" dialog; it is stored on the polygon,
returned in list / Feature responses, and exported to / imported from the Shapefile as `DESCRIP`.

Processing: points keep their recorded order (`lng lat`); fixes with `accuracy` above the threshold and
consecutive duplicates are dropped; the ring is closed automatically; `ST_MakeValid` is applied and the
largest polygon is kept (a self-intersecting walk becomes a valid polygon). Area / perimeter come from
`::geography` (m2 / m). A straight walk encloses ~0 area and is rejected with 422 - but the walked path is
always kept in `track` for polygons that are saved.

#### Create a polygon (online, or one item of the offline queue file)

```bash
curl -X POST http://127.0.0.1:8083/api/polygons \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{
    "uuid": "5b1f0c1e-7a0e-4b53-9d0b-3a8f5f0f2c11",
    "description": "Boundary walk of the north field",
    "started_at": "2026-10-05T10:00:00+05:30",
    "ended_at": "2026-10-05T10:25:00+05:30",
    "source": "online",
    "points": [
      {"lat": 29.1492, "lng": 75.7217, "accuracy": 5.2, "timestamp": "2026-10-05T10:00:03+05:30"},
      {"lat": 29.1492, "lng": 75.7227, "accuracy": 4.8, "timestamp": "2026-10-05T10:00:07+05:30"},
      {"lat": 29.1501, "lng": 75.7227, "accuracy": 5.0, "timestamp": "2026-10-05T10:00:11+05:30"},
      {"lat": 29.1501, "lng": 75.7217, "accuracy": 5.1, "timestamp": "2026-10-05T10:00:15+05:30"}
    ],
    "attributes": { "owner_name": "Ramlal", "khasra_no": "12/3", "village": "Satrod" }
  }'
```

Response `201` (`area_sqm` / `perimeter_m` are illustrative; real values come from PostGIS):

```json
{
  "success": true,
  "message": "Polygon saved",
  "data": {
    "type": "Feature",
    "id": "5b1f0c1e-7a0e-4b53-9d0b-3a8f5f0f2c11",
    "geometry": { "type": "Polygon", "coordinates": [[[75.7217,29.1492],[75.7227,29.1492],[75.7227,29.1501],[75.7217,29.1501],[75.7217,29.1492]]] },
    "properties": {
      "id": 1, "uuid": "5b1f0c1e-7a0e-4b53-9d0b-3a8f5f0f2c11", "description": "Boundary walk of the north field",
      "area_sqm": 9720.4, "perimeter_m": 395.1, "point_count": 4,
      "started_at": "2026-10-05T10:00:00+05:30", "ended_at": "2026-10-05T10:25:00+05:30",
      "source": "online", "created_at": "2026-10-05T10:26:02+05:30", "has_data": true,
      "owner_name": "Ramlal", "father_name": null, "mobile": null, "village": "Satrod", "tehsil": null,
      "district": null, "khasra_no": "12/3", "murabba_no": null, "crop": null, "remarks": null,
      "extra": {},
      "track": { "type": "LineString", "coordinates": [[75.7217,29.1492],[75.7227,29.1492],[75.7227,29.1501],[75.7217,29.1501]] }
    }
  }
}
```

#### Offline sync (bulk)

Save the same objects (same client-generated `uuid`) in a local JSON array while offline, then send it
later. Already-synced uuids come back as `duplicate`, never as new rows.

```bash
curl -X POST http://127.0.0.1:8083/api/polygons/bulk \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d @offline_queue.json
# -> {"success":true,"message":"2 created, 1 duplicate, 0 failed","data":{"summary":{"created":2,"duplicate":1,"failed":0},"results":[{"index":0,"uuid":"...","status":"created","data":{...}}, ...]}}
```

#### List, map, read, delete

```bash
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8083/api/polygons?village=Satrod&has_data=true&bbox=75.7,29.1,75.8,29.2"
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8083/api/polygons/geojson"
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8083/api/polygons/5b1f0c1e-7a0e-4b53-9d0b-3a8f5f0f2c11"
curl -X DELETE -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8083/api/polygons/5b1f0c1e-7a0e-4b53-9d0b-3a8f5f0f2c11"
```

#### Attributes (separate table)

```bash
# create or update (omitted fields are kept; unknown keys and "extra" are merged into the jsonb column)
curl -X PUT http://127.0.0.1:8083/api/polygons/5b1f0c1e-7a0e-4b53-9d0b-3a8f5f0f2c11/attributes \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{ "crop": "Wheat", "extra": { "irrigation": "canal" } }'

curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8083/api/polygons/5b1f0c1e-7a0e-4b53-9d0b-3a8f5f0f2c11/attributes
curl -X DELETE -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8083/api/polygons/5b1f0c1e-7a0e-4b53-9d0b-3a8f5f0f2c11/attributes
```

#### Shapefile export / import

```bash
# export everything, a village, a bbox, or specific polygon ids
curl -H "Authorization: Bearer $TOKEN" -o polygons.zip "http://127.0.0.1:8083/api/polygons/export/shp?village=Satrod"
curl -H "Authorization: Bearer $TOKEN" -o polygons.zip "http://127.0.0.1:8083/api/polygons/export/shp?ids[]=1&ids[]=2"

# import a zip (must contain .shp .shx .dbf; .prj/.cpg optional)
curl -X POST http://127.0.0.1:8083/api/polygons/import/shp \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" -F "file=@polygons.zip"
# -> {"success":true,"message":"2 polygon(s) imported, 0 feature(s) skipped","data":{"features":2,"imported":2,"skipped":0,"skipped_details":[],"warnings":[]}}
```

Shapefile notes:

- **Field names are max 10 characters**, so each column is exported under the alias in `config/survey.php`
  (`owner_name` -> `OWNER`, `khasra_no` -> `KHASRA`, `murabba_no` -> `MURABBA`, `area_sqm` -> `AREA_SQM`,
  `perimeter_m` -> `PERIM_M`, `uuid` -> `UUID`, `description` -> `DESCRIP`, `extra` -> `EXTRA` as JSON text). On import the same list maps
  DBF fields back to columns (case-insensitive); unmapped fields go to `extra`. `UUID`, `AREA_SQM`, `PERIM_M`
  are derived values and are ignored; imported polygons get fresh uuids and `source = shp_import`.
- **Hindi text**: export uses `-lco ENCODING=UTF-8` (writes the `.cpg`). On import a missing `.cpg` is treated as
  UTF-8 and reported in `warnings`. DBF text fields hold at most 254 bytes, so long text (e.g. `remarks`) is cut on export.
- **Projection**: import reprojects to EPSG:4326 when a `.prj` is present; without one, 4326 is assumed (warning).
- MultiPolygons are exploded into separate rows; non-polygon, empty, zero-area or out-of-range features are
  skipped and listed in `skipped_details`. Staging table and temp files (`storage/app/tmp`) are removed even on errors.
- ogr2ogr is started without a shell, filters reach it only as validated integer ids, and the DB password is
  passed via `PGPASSWORD` rather than the command line.

### Tests

`tests/Feature/SurveyPolygonApiTest.php` needs a PostGIS database, by default `mhari_panchayat_test` on
127.0.0.1:5432 (override with `TRACKING_TEST_DB_*`), and GDAL for the Shapefile tests. Tests skip when these
are unavailable. They commit real rows (ogr2ogr uses its own DB connection) and clean up the users they create.

## Asset survey Excel export

`GET /api/surveys/export` (Bearer token) downloads an `.xlsx` of the asset surveys that match the same
filters as the Asset Surveys list: `q` (search), `condition` (GOOD/FAIR/POOR/DAMAGED) and `review_status`.
It respects the same visibility rules as the list (a surveyor only gets their own, reviewers only their
jurisdiction). Each row has the survey details, review status, the first 3 photos embedded as pictures and a
column with links to all photos. Photos over 800 KB (or past a 150 MB workbook budget) become clickable links
instead, so the file stays small. At most 1500 surveys per export - narrow the filters beyond that (422).
No image library is needed (the workbook is written with ext-zip only), so it also works without GD.
The admin panel's Asset Surveys screen has an **Export Excel** button that passes its current filters.
