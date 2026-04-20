library(terrascoper)
library(terra)

# --- Config ---
output_dir <- "data/raw"
collection <- "terrascope-s5p-l3-no2-tm-v2"  # Monthly tropospheric NO2
bbox       <- c(-180, -85, 180, 85)           # Global

# Date range
start_date <- "2018-01-01"
end_date   <- "2026-03-28"

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

# Companion weight band: per-pixel L2->L3 binning weights. Needed to do a
# weight-aware aggregation in process.R so low-coverage pixels (e.g. polar
# night at high northern latitudes in winter) stop polluting the mean.
download_terrascope(
  bbox       = bbox,
  start_date = start_date,
  end_date   = end_date,
  output_dir = output_dir,
  collection = collection,
  asset_key  = "NO2_WEIGHT",
  file_prefix = "no2weight"
)

# --- Preview PNGs for visual QC ---
# One PNG per raw GeoTIFF, saved next to the data. Skips files that already
# have a preview so repeated runs are cheap. Auto-scales color range per file
# so you can spot anomalous months.
preview_dir <- file.path(output_dir, "previews")
dir.create(preview_dir, showWarnings = FALSE, recursive = TRUE)

tif_files <- list.files(output_dir, pattern = "^no2_monthly_.*\\.tif$", full.names = TRUE)
tif_files <- tif_files[!grepl("\\.aux\\.xml", tif_files)]

cat("\nGenerating preview PNGs...\n")
for (f in tif_files) {
  png_file <- file.path(preview_dir, sub("\\.tif$", ".png", basename(f)))
  if (file.exists(png_file)) next

  cat("  ", basename(png_file), "\n")
  r <- rast(f)
  png(png_file, width = 1600, height = 800)
  plot(r,
       col = hcl.colors(100, "YlOrRd", rev = TRUE),
       main = basename(f))
  dev.off()
  rm(r)
}
cat("Previews saved to:", preview_dir, "\n")
