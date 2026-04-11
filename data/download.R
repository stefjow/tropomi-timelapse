library(terrascoper)

# --- Config ---
output_dir <- "data/raw"
collection <- "terrascope-s5p-l3-no2-tm-v2"  # Monthly tropospheric NO2
bbox       <- c(-180, -85, 180, 85)           # Global

# Date range
start_date <- "2024-01-01"
end_date   <- "2025-12-28"

# --- Download ---
download_terrascope(
  bbox       = bbox,
  start_date = start_date,
  end_date   = end_date,
  output_dir = output_dir,
  collection = collection,
  asset_key  = "NO2",
  file_prefix = "no2_monthly"
)
