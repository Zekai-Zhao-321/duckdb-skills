# Overture Maps

Free global map data — places, buildings, roads, boundaries, addresses — published as
GeoParquet on public S3. No API key, no registration, no download. Use it when the user
asks about real-world locations and has supplied no data of their own.

Read `spatial.md` first, particularly the axis-order section — every distance below
depends on it.

## Setup

```sql
INSTALL httpfs; INSTALL spatial;
LOAD httpfs; LOAD spatial;
CREATE SECRET (TYPE s3, PROVIDER config, REGION 'us-west-2');
```

The bucket is public, so no credentials — but the region must be `us-west-2`.

## Paths

```
s3://overturemaps-us-west-2/release/<RELEASE>/theme=<THEME>/type=<TYPE>/*
```

| Theme | Type | What it holds |
|---|---|---|
| `places` | `place` | POIs — shops, restaurants, services |
| `buildings` | `building` | Footprints, heights, floor counts |
| `transportation` | `segment` | Road and rail centrelines |
| `divisions` | `division` | Administrative places (points) |
| `divisions` | `division_area` | Administrative boundaries (polygons) |
| `addresses` | `address` | Street addresses |
| `base` | `land`, `water`, `land_use`, … | Physical features |

Releases are dated, e.g. `2026-03-18.0`. Find the current one from the STAC catalog at
<https://stac.overturemaps.org/catalog.json> rather than assuming — a stale release
string produces an empty result, not an error. If you cannot reach the catalog, say so
and ask the user for the release they want.

## Always filter on bbox first

Every file carries `bbox.xmin/xmax/ymin/ymax` columns. Filtering on them lets Parquet
skip whole row groups, turning a terabyte scan into a few megabytes. A query without a
bbox filter will appear to hang.

```sql
FROM read_parquet('s3://overturemaps-us-west-2/release/2026-03-18.0/theme=places/type=place/*')
WHERE bbox.xmin BETWEEN -74.01 AND -73.96      -- longitude
  AND bbox.ymin BETWEEN  40.72 AND  40.77      -- latitude
```

Pick the box from the area of interest, not the other way round: a city is roughly
0.1–0.3 degrees across, a neighbourhood roughly 0.01–0.03.

## Fields

**places**: `id`, `geometry` (point), `bbox`, `names.primary`, `categories.primary`
(e.g. `coffee_shop`, `restaurant`, `hospital`), `categories.alternate`, `confidence`
(0–1), `addresses[1].freeform`, `addresses[1].locality`, `websites`, `phones`,
`brand.names.primary`.

**buildings**: `id`, `geometry` (polygon), `bbox`, `names.primary` (often null), `class`,
`height` (metres), `num_floors`, `roof_shape`.

**transportation/segment**: `id`, `geometry` (linestring), `names.primary`, `class`
(`motorway`, `primary`, `secondary`, `residential`, …), `subtype` (`road`, `rail`,
`water`), `speed_limits`.

**divisions/division**: `id`, `geometry` (point), `names.primary`, `subtype` (`country`,
`region`, `county`, `locality`, …), `admin_level`, `population`, `country` (ISO 3166-1
alpha-2). **division_area** adds a `MultiPolygon` `geometry` and `division_id`.

Nested fields are structs — `names.primary`, not `name`. `DESCRIBE` a single file if a
field is not where you expect; the schema does change between releases.

## Examples

```sql
-- Coffee shops near Times Square, nearest first
SELECT names.primary AS name,
       addresses[1].freeform AS address,
       ST_Distance_Spheroid(
         ST_Point2D(ST_Y(geometry), ST_X(geometry)),   -- (lat, lng) for spheroid
         ST_Point2D(40.7580, -73.9855)
       ) AS meters
FROM read_parquet('s3://overturemaps-us-west-2/release/2026-03-18.0/theme=places/type=place/*')
WHERE bbox.xmin BETWEEN -74.00 AND -73.97
  AND bbox.ymin BETWEEN  40.74 AND  40.77
  AND categories.primary = 'coffee_shop'
ORDER BY meters LIMIT 10;
```

```sql
-- Tallest buildings in a bounding box
SELECT names.primary AS name, height, num_floors
FROM read_parquet('s3://overturemaps-us-west-2/release/2026-03-18.0/theme=buildings/type=building/*')
WHERE bbox.xmin BETWEEN -122.42 AND -122.39
  AND bbox.ymin BETWEEN   37.78 AND   37.80
  AND height IS NOT NULL
ORDER BY height DESC LIMIT 10;
```

```sql
-- Enrich a user's CSV with the nearest Overture place
FROM 'locations.csv' u
CROSS JOIN LATERAL (
    FROM read_parquet('s3://overturemaps-us-west-2/release/2026-03-18.0/theme=places/type=place/*')
    WHERE bbox.xmin BETWEEN u.longitude - 0.01 AND u.longitude + 0.01
      AND bbox.ymin BETWEEN u.latitude  - 0.01 AND u.latitude  + 0.01
    ORDER BY ST_Distance(ST_Point(u.longitude, u.latitude), geometry)
    LIMIT 1
) p
SELECT u.*, p.names.primary AS nearest_place, p.categories.primary AS category;
```

## No results?

In this order: widen the bbox; confirm the release string against the STAC catalog;
check the category spelling by listing what is actually there
(`SELECT DISTINCT categories.primary … LIMIT 50`); confirm longitude and latitude are
not swapped in the filter. An empty result from Overture is almost always the query, not
the data.
