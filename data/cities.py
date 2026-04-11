#!/usr/bin/env python3
"""Convert simplemaps world cities CSV to filtered GeoJSON for the web app."""

import csv
import json

INPUT = "simplemaps_worldcities_basicv1.901/worldcities.csv"
OUTPUT = "public/data/cities.geojson"
MIN_POPULATION = 100_000

cities = []
with open(INPUT) as f:
    for row in csv.DictReader(f):
        pop = row.get("population", "")
        if not pop:
            continue
        pop = int(float(pop))
        if pop < MIN_POPULATION:
            continue
        cities.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [float(row["lng"]), float(row["lat"])]},
            "properties": {
                "name": row["city"],
                "country": row["country"],
                "population": pop,
            },
        })

geojson = {"type": "FeatureCollection", "features": cities}
with open(OUTPUT, "w") as f:
    json.dump(geojson, f)

print(f"Wrote {len(cities)} cities (pop >= {MIN_POPULATION:,}) to {OUTPUT}")
