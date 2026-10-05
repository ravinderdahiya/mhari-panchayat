<?php

return [

    /*
    | GPS fixes reported with a horizontal accuracy worse (larger) than this many
    | metres are dropped before the boundary is built. Points that arrive without
    | an accuracy value are kept.
    */
    'max_accuracy_m' => (float) env('TRACKING_MAX_ACCURACY_M', 30),

    // Minimum number of distinct points (after cleaning) needed to form a polygon.
    'min_points' => (int) env('TRACKING_MIN_POINTS', 3),

    // Polygons smaller than this (m2) are treated as empty - e.g. a walk along a
    // straight road, which leaves only a floating-point sliver.
    'min_area_sqm' => (float) env('TRACKING_MIN_AREA_SQM', 1),

    // Upper bound on points in a single track, to keep request size sane.
    'max_points' => (int) env('TRACKING_MAX_POINTS', 20000),

    // Max tracks accepted by one POST /api/tracked-areas/bulk call.
    'bulk_max' => (int) env('TRACKING_BULK_MAX', 50),

    // Max features returned by GET /api/tracked-areas/geojson.
    'geojson_limit' => (int) env('TRACKING_GEOJSON_LIMIT', 1000),

];
