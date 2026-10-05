<?php

return [

    /*
    | Fixed columns of survey_polygon_attributes: column => max length.
    | They are validated from this list; any other key sent in `attributes`
    | is stored in the `extra` jsonb column, so new fields need no code change
    | (add a column + an entry here only when it should be a real column).
    */
    'attribute_fields' => [
        'owner_name' => 255,
        'father_name' => 255,
        'mobile' => 20,
        'village' => 255,
        'tehsil' => 255,
        'district' => 255,
        'khasra_no' => 100,
        'murabba_no' => 100,
        'crop' => 255,
        'remarks' => 2000,
    ],

    /*
    | Shapefile (DBF) field names are limited to 10 characters, so every column
    | is exported under an explicit alias. The same map is used (case-insensitive)
    | to map DBF fields back to columns on import; unmapped fields go to `extra`.
    */
    'shp_aliases' => [
        'owner_name' => 'OWNER',
        'father_name' => 'FATHER',
        'mobile' => 'MOBILE',
        'village' => 'VILLAGE',
        'tehsil' => 'TEHSIL',
        'district' => 'DISTRICT',
        'khasra_no' => 'KHASRA',
        'murabba_no' => 'MURABBA',
        'crop' => 'CROP',
        'remarks' => 'REMARKS',
    ],

    // Polygon-level columns exported to the shapefile (derived on import, so ignored there).
    'shp_polygon_aliases' => [
        'uuid' => 'UUID',
        'area_sqm' => 'AREA_SQM',
        'perimeter_m' => 'PERIM_M',
    ],

    // Alias for the `extra` jsonb column (exported as JSON text).
    'shp_extra_alias' => 'EXTRA',

    'gdal' => [
        // Full path when GDAL is not on PATH (e.g. C:\Program Files\QGIS 4.0.0\bin\ogr2ogr.exe).
        'ogr2ogr' => env('OGR2OGR_BIN', 'ogr2ogr'),
        'ogrinfo' => env('OGRINFO_BIN', 'ogrinfo'),
        'timeout' => (int) env('GDAL_TIMEOUT', 180),
        // Optional: GDAL/PROJ data folders for the ogr2ogr process. Needed when another
        // install (e.g. PostgreSQL/PostGIS) has already set GDAL_DATA / PROJ_LIB globally.
        'data_dir' => env('GDAL_DATA_DIR'),
        'proj_dir' => env('GDAL_PROJ_DIR'),
    ],

    'shp' => [
        'tmp_dir' => 'tmp', // under storage/app
        'max_upload_kb' => (int) env('SHP_MAX_UPLOAD_KB', 20480),
        'max_unzipped_mb' => (int) env('SHP_MAX_UNZIPPED_MB', 200),
        'max_features' => (int) env('SHP_MAX_FEATURES', 5000),
        'max_export' => (int) env('SHP_MAX_EXPORT', 5000),
    ],

];
