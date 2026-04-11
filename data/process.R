library(terra)
library(jsonlite)

# --- Config ---
input_dir  <- "data/raw"
# Mode: "monthly" for raw monthly data, "rolling" for 12-month rolling mean
mode       <- "rolling"
output_dir <- file.path("public/tiles", mode)
tmp_dir    <- file.path(output_dir, "tmp")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)

# Max zoom level for tile pyramid (0 = whole world in 1 tile, 3 = testing)
max_zoom <- 0

# Set to TRUE to force recalculation of all months (ignores existing PMTiles)
force_recalc <- TRUE

# Color scale: hot-body with blue peaks (inspired by libmap.org NO2 layer)
# Tuned for NO2 tropospheric column (µmol/m²)
scale_min <- 0
scale_max <- 150

no2_colors <- c(
  "#e85555",  # lightest red
  "#d94040",  # light red
  "#c43030",  # light red
  "#a52020",  # red
  "#8b1a1a",  # dark red
  "#6b1010",  # deeper red
  "#4a0c0c",  # very dark red
  "#c43c2d",  # red-orange
  "#e06830",  # orange
  "#f0a030",  # golden orange
  "#f8d040",  # yellow-orange
  "#fff06a",  # bright yellow
  "#c8f0ff",  # light ice blue
  "#7ecbff",  # blue
  "#3a8fd4",  # medium blue
  "#1a5a9e",  # dark blue
  "#0e3a6e",  # deep blue
  "#061a3a",  # very dark blue
  "#000000"   # black (extreme peaks)
)

# Write GDAL color relief file (maps NO2 values directly to RGBA)
color_rgb <- col2rgb(no2_colors)
breaks <- seq(scale_min, scale_max, length.out = length(no2_colors))
color_file <- file.path(tmp_dir, "no2_colors.txt")
writeLines(c(
  "nv 0 0 0 0",
  sprintf("%.2f %d %d %d 255", breaks, color_rgb[1, ], color_rgb[2, ], color_rgb[3, ]),
  # Clamp everything above scale_max to the last color
  sprintf("%.2f %d %d %d 255", 9999, color_rgb[1, length(no2_colors)],
          color_rgb[2, length(no2_colors)], color_rgb[3, length(no2_colors)])
), color_file)

# --- Find monthly files ---
tif_files <- sort(list.files(input_dir, pattern = "\\.tif$", full.names = TRUE))
tif_files <- tif_files[!grepl("\\.aux\\.xml", tif_files)]

if (length(tif_files) == 0) {
  stop("No .tif files found in ", input_dir, ". Run download.R first.")
}

# Extract YYYY-MM from filenames (expects date like 20260101 in filename)
dates <- regmatches(basename(tif_files), regexpr("\\d{8}", basename(tif_files)))
month_labels <- paste0(substr(dates, 1, 4), "-", substr(dates, 5, 6))

cat("Found", length(tif_files), "monthly files:\n")
cat(paste(" ", month_labels, "->", basename(tif_files)), sep = "\n")

# Parse dates for rolling mean lookups
file_dates <- as.Date(dates, format = "%Y%m%d")

metadata <- list(
  months = list(),
  bbox   = c(-180, -85, 180, 85),
  scale  = list(min = scale_min, max = scale_max, unit = "\u00b5mol/m\u00b2"),
  colors = colorRampPalette(no2_colors)(10)
)

for (i in seq_along(tif_files)) {
  month_label <- month_labels[i]
  pmt_path <- file.path(output_dir, paste0("no2_", month_label, ".pmtiles"))

  if (!force_recalc && file.exists(pmt_path)) {
    cat("\nSkipping:", month_label, "(already exists)\n")
    metadata$months <- c(metadata$months, list(month_label))
    next
  }

  cat("\nProcessing:", month_label, "\n")

  if (mode == "rolling") {
    # Find all files within the preceding 12 months (inclusive of current)
    target_date <- file_dates[i]
    window_start <- seq(target_date, length = 2, by = "-11 months")[2]
    in_window <- which(file_dates >= window_start & file_dates <= target_date)
    if (length(in_window) < 12) {
      cat("  Skipping: only", length(in_window), "of 12 months available\n")
      next
    }
    cat("  Rolling mean over", length(in_window), "months:",
        paste(month_labels[in_window], collapse = ", "), "\n")
    stack <- rast(lapply(tif_files[in_window], rast))
    r <- mean(stack, na.rm = TRUE)
    rm(stack)
    gc(verbose = FALSE)
  } else {
    r <- rast(tif_files[i])
  }

  # Crop latitude to ~85° (Web Mercator limit)
  # Note: terra auto-applies scale/offset from file metadata during operations
  r <- crop(r, ext(-180, 180, -85, 85))

  # Write single-band temp GeoTIFF (NO2 values in µmol/m²)
  single_path <- file.path(tmp_dir, paste0("no2_", month_label, "_single.tif"))
  writeRaster(r, single_path, overwrite = TRUE)
  rm(r)
  gc(verbose = FALSE)

  # Apply color relief via GDAL -> RGBA GeoTIFF (no large R matrices needed)
  tif_path <- file.path(tmp_dir, paste0("no2_", month_label, "_rgba.tif"))
  gdaldem_cmd <- sprintf(
    'gdaldem color-relief -alpha "%s" "%s" "%s"',
    single_path, color_file, tif_path
  )
  cat("  Applying color relief...\n")
  system(gdaldem_cmd)

  # Convert to MBTiles at max zoom
  mbt_path <- file.path(tmp_dir, paste0("no2_", month_label, ".mbtiles"))
  gdal_cmd <- sprintf(
    'gdal_translate -of MBTiles -co "TILE_FORMAT=PNG" -co "RESAMPLING=AVERAGE" -co "ZOOM_LEVEL_STRATEGY=UPPER" "%s" "%s"',
    tif_path, mbt_path
  )
  cat("  Creating MBTiles at zoom", max_zoom, "...\n")
  system(gdal_cmd)

  # Add lower zoom overviews (factors go down to zoom 0 from whatever base GDAL chose)
  overviews <- paste(2^(1:10), collapse = " ")
  addo_cmd <- sprintf('gdaladdo -r average "%s" %s', mbt_path, overviews)
  cat("  Adding overview levels...\n")
  system(addo_cmd)

  # Convert MBTiles to PMTiles
  pmt_cmd <- sprintf('pmtiles convert "%s" "%s"', mbt_path, pmt_path)
  cat("  Converting to PMTiles...\n")
  system(pmt_cmd)

  file_size <- file.info(pmt_path)$size / (1024 * 1024)
  cat("  Written:", pmt_path, "(", round(file_size, 1), "MB )\n")

  metadata$months <- c(metadata$months, list(month_label))

  # Clean up temp files
  unlink(single_path)
  unlink(tif_path)
  unlink(mbt_path)
  gc(verbose = FALSE)
}

# Clean up tmp directory
unlink(tmp_dir, recursive = TRUE)

# Write metadata
meta_path <- file.path(output_dir, "metadata.json")
writeLines(toJSON(metadata, auto_unbox = TRUE, pretty = TRUE), meta_path)
cat("\nMetadata written to:", meta_path, "\n")
cat("Done! Generated", length(tif_files), "monthly PMTiles.\n")
