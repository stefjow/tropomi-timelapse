# TROPOMI NO2 Timelapse

Interactive map visualization of global nitrogen dioxide (NO2) tropospheric column density from the Sentinel-5P TROPOMI instrument.

Live at: [no2.bbble.org](https://no2.bbble.org)

## Overview

Monthly NO2 data from ESA's Sentinel-5P satellite is downloaded, processed into PMTiles, and displayed on an interactive MapLibre GL JS map. Supports two modes:

- **Monthly** -- raw monthly averages
- **Rolling** -- 12-month rolling mean (smooths seasonal variation)

## Project structure

```
tropomi-timelapse/
├── public/                     # static site (deploy this)
│   ├── index.html
│   ├── app.js
│   ├── style.css
│   ├── config.json             # mode, title, tile directory
│   ├── data/cities.geojson     # filtered world cities
│   └── tiles/
│       ├── monthly/            # monthly PMTiles + metadata
│       └── rolling/            # rolling mean PMTiles + metadata
├── data/                       # processing pipeline
│   ├── download.R              # fetch raw TIFs from Terrascope
│   ├── process.R               # TIF → color relief → MBTiles → PMTiles
│   ├── cities.py               # simplemaps CSV → GeoJSON
│   └── raw/                    # raw satellite TIFs (gitignored)
└── simplemaps_worldcities_basicv1.901/
    └── worldcities.csv         # source city data
```

## Prerequisites

- **R** with packages: `terra`, `jsonlite`, `terrascoper`
- **GDAL** (`gdaldem`, `gdal_translate`, `gdaladdo`)
- **pmtiles** CLI (`pmtiles convert`)
- **Python 3** (for cities.py)

## Usage

### 1. Download satellite data

Edit date range in `data/download.R`, then:

```bash
Rscript data/download.R
```

Skips files already in `data/raw/`.

### 2. Generate city data

```bash
python3 data/cities.py
```

### 3. Process tiles

Edit `data/process.R` to set:
- `mode` -- `"monthly"` or `"rolling"`
- `scale_max` -- upper bound of color scale (in umol/m2)
- `max_zoom` -- tile pyramid depth
- `force_recalc` -- `TRUE` to regenerate all tiles

```bash
Rscript data/process.R
```

Skips months that already have a `.pmtiles` file unless `force_recalc` is `TRUE`.

### 4. Configure the frontend

Edit `public/config.json` to point to the desired tile set:

```json
{
  "title": "Monthly NO\u2082 Averages",
  "subtitle": "Tropospheric column density from TROPOMI",
  "tilesDir": "tiles/monthly"
}
```

### 5. Serve

Any static file server with HTTP Range request support:

```bash
cd public && npx serve -p 8000
```

For production, point nginx/caddy at the `public/` directory.

## Data sources

- **NO2 data**: [Terrascope](https://terrascope.be) / ESA Sentinel-5P TROPOMI (Collection: `terrascope-s5p-l3-no2-tm-v2`)
- **Cities**: [Simplemaps World Cities](https://simplemaps.com/data/world-cities) (CC BY 4.0)
- **Basemaps**: [CARTO](https://carto.com/basemaps) (dark), [Esri](https://www.esri.com) (satellite)
