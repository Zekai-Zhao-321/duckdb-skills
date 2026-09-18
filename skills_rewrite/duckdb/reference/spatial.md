# Spatial data

Canonical pages: `docs/core_extensions/spatial/functions.md` (every function with its
exact signature), `docs/core_extensions/spatial/overview.md`,
`docs/sql/data_types/geometry.md`, `docs/sql/functions/geometry.md`.

```sql
INSTALL spatial; LOAD spatial;
```

`GEOMETRY` is a built-in type from DuckDB v1.5, but almost every function below comes
from the `spatial` extension, so load it.

## Read this before computing any distance

Two different axis orders are in play, and mixing them up produces plausible-looking
numbers that are badly wrong.

- **Stored data is `(x, y)` = `(longitude, latitude)`.** GeoJSON, Shapefiles, Overture,
  GeoParquet and a CSV with `longitude`/`latitude` columns all use this order.
  Build geometries with `ST_Point(longitude, latitude)` — longitude first.
- **Every `_Spheroid` function expects `(latitude, longitude)`.** The docs are explicit:
  `ST_Distance_Spheroid`, `ST_DWithin_Spheroid`, `ST_Area_Spheroid` and
  `ST_Length_Spheroid` all assume WGS84 in `[latitude, longitude]` axis order. You must
  swap the coordinates on the way in.
- `ST_Distance_Spheroid` and `ST_DWithin_Spheroid` additionally accept only `POINT_2D`,
  not `GEOMETRY`. `ST_Point2D(a, b)` constructs one directly.

So, going from a stored geometry column to a real-world distance in meters:

```sql
-- geom holds (lng, lat); the spheroid function wants (lat, lng) → swap with ST_X/ST_Y
SELECT ST_Distance_Spheroid(
         ST_Point2D(ST_Y(a.geom), ST_X(a.geom)),
         ST_Point2D(ST_Y(b.geom), ST_X(b.geom))
       ) AS meters
FROM places a, places b;
```

**Always sanity-check the axis order with a distance you know** before trusting a batch
of results. From the DuckDB docs, JFK to Amsterdam is about 5,863 km:

```sql
SELECT ST_Distance_Spheroid(ST_Point2D(40.6446, -73.7797),
                            ST_Point2D(52.3130, 4.7725)) / 1000 AS km;
-- ≈ 5863.4
```

If your number is wildly off, you have the coordinates the wrong way round. Swap an
existing geometry with `ST_FlipCoordinates(geom)`.

Plain `ST_Distance` is planar and accepts any `GEOMETRY`. On lat/lng input its result is
in degrees, which is meaningless as a distance but fine for *ordering* nearby
candidates. Use it to shortlist, then `ST_Distance_Spheroid` to measure.

Older material may tell you to `SET geometry_always_xy = true`. That setting is not in
the current documentation — do not rely on it; handle axis order explicitly instead.

## Reading and writing

| Format | Read | Write |
|---|---|---|
| GeoJSON | `ST_Read('f.geojson')` | `(FORMAT gdal, DRIVER 'GeoJSON')` |
| Shapefile | `ST_Read('f.shp')` | `(FORMAT gdal, DRIVER 'ESRI Shapefile')` |
| GeoPackage | `ST_Read('f.gpkg')` | `(FORMAT gdal, DRIVER 'GPKG')` |
| FlatGeobuf | `ST_Read('f.fgb')` | `(FORMAT gdal, DRIVER 'FlatGeobuf')` |
| KML / GPX | `ST_Read('f.kml')` | `(FORMAT gdal, DRIVER 'KML')` |
| GeoParquet | `FROM 'f.parquet'` | `COPY … TO 'f.parquet'` |
| CSV with lat/lng | `SELECT *, ST_Point(lng, lat) AS geom FROM 'f.csv'` | — |

```sql
COPY (SELECT name, geom FROM results)
TO 'out.geojson' WITH (FORMAT gdal, DRIVER 'GeoJSON');
```

`ST_Read` wraps GDAL and handles 50+ formats; it also powers replacement scans, so
`FROM 'f.shp'` works directly. Pass options — `layer`, `spatial_filter_box` — by calling
`ST_Read` explicitly.

## Functions you will reach for

| Purpose | Functions |
|---|---|
| Construct | `ST_Point(x, y)`, `ST_Point2D(x, y)`, `ST_GeomFromText(wkt)`, `ST_GeomFromGeoJSON(j)`, `ST_MakeEnvelope(xmin, ymin, xmax, ymax)` |
| Relate | `ST_Contains`, `ST_Within`, `ST_Intersects`, `ST_Covers`, `ST_Touches`, `ST_Disjoint` |
| Measure | `ST_Distance`, `ST_Distance_Spheroid`, `ST_DWithin`, `ST_DWithin_Spheroid`, `ST_Area`, `ST_Area_Spheroid`, `ST_Length`, `ST_Length_Spheroid`, `ST_Perimeter` |
| Transform | `ST_Transform(geom, 'EPSG:4326', 'EPSG:3857')`, `ST_Centroid`, `ST_Buffer`, `ST_Simplify`, `ST_ConvexHull`, `ST_FlipCoordinates` |
| Combine | `ST_Union`, `ST_Intersection`, `ST_Difference`, `ST_Union_Agg`, `ST_Extent_Agg`, `ST_Collect` |
| Inspect | `ST_X`, `ST_Y`, `ST_GeometryType`, `ST_AsText`, `ST_AsGeoJSON`, `ST_XMin`/`XMax`/`YMin`/`YMax`, `ST_NPoints`, `ST_IsValid` |

Check the exact signature in `docs/core_extensions/spatial/functions.md` before using
one you have not used recently — several have narrow type overloads.

## Patterns

```sql
-- Points inside polygons
SELECT p.name, z.zone
FROM points p JOIN zones z ON ST_Contains(z.geom, p.geom);

-- Nearest 3 targets per row: shortlist planar, then measure
FROM locations a
CROSS JOIN LATERAL (
    FROM targets t
    ORDER BY ST_Distance(a.geom, t.geom)
    LIMIT 3
) t
SELECT a.name, t.name AS nearest,
       ST_Distance_Spheroid(ST_Point2D(ST_Y(a.geom), ST_X(a.geom)),
                            ST_Point2D(ST_Y(t.geom), ST_X(t.geom))) AS meters;

-- Bounding box of a dataset (useful before picking a map extent)
SELECT ST_Extent_Agg(geom) FROM features;
```

On large datasets, filter by bounding box before calling any spatial predicate —
comparing `xmin`/`xmax`/`ymin`/`ymax` is cheap and skips most rows. An R-tree index
(`docs/core_extensions/spatial/r-tree_indexes.md`) speeds up repeated predicates on a
persistent table.

## H3 hexagonal binning

For density maps and hotspot analysis. Community extension:

```sql
INSTALL h3 FROM community; LOAD h3;

SELECT h3_latlng_to_cell(lat, lng, 7) AS hex,
       count() AS n,
       h3_cell_to_boundary_wkt(hex) AS boundary
FROM points
GROUP BY hex ORDER BY n DESC;
```

| Resolution | Approx. edge | Scale |
|---|---|---|
| 3 | 59 km | Regions |
| 5 | 8 km | Cities |
| 7 | 1.2 km | Neighbourhoods |
| 9 | 174 m | City blocks |
| 11 | 25 m | Buildings |

Also: `h3_cell_to_latlng(cell)`, `h3_grid_disk(cell, k)` for the k-ring around a cell.

## Presenting results

Report distances in the unit that fits — metres below a kilometre, kilometres above.
When the result is a set of geometries, offer to write a GeoJSON file the user can drop
into a map viewer; a table of WKT strings is rarely what they wanted.
