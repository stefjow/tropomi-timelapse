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

# Cap terra memory budget and point its spill directory at disk (not tmpfs),
# so large stack operations don't balloon RAM use. Adjust memfrac if your
# machine has plenty of RAM free.
terraOptions(memfrac = 0.3, tempdir = tmp_dir)

# Cap GDAL's internal tile cache (default auto-sizes to a big % of RAM).
# 512 MB is plenty for tile generation.
Sys.setenv(GDAL_CACHEMAX = "512")

# Best-effort cleanup of this session's tempdir on exit. R does this on normal
# exit, but be explicit so an interrupted/resumed session still clears spill.
on.exit(unlink(tempdir(), recursive = TRUE, force = TRUE), add = TRUE)

# Max zoom level for tile pyramid (0 = whole world in 1 tile, 3 = testing)
# Source S5P L3 data is ~0.05° (~5 km) per pixel; that matches zoom ~5.
# Going higher just interpolates fake detail and bloats file sizes — MapLibre
# can upsample client-side just fine beyond max zoom.
max_zoom <- 0

# Set to TRUE to force recalculation of all months (ignores existing PMTiles)
force_recalc <- FALSE

# Color scale: hot-body with blue peaks (inspired by libmap.org NO2 layer)
# Tuned for NO2 tropospheric column (µmol/m²)
scale_min <- 0
scale_max <- 170

# Set TRUE to inspect data distribution and print a recommended scale_max before
# tile generation. Leave FALSE for normal runs (skips the extra I/O pass).
inspect_scale <- FALSE

# Old palette (libmap-inspired, non-monotonic lightness; kept for reference):
# no2_colors <- c(
#   "#e85555",  # lightest red
#   "#d94040",  # light red
#   "#c43030",  # light red
#   "#a52020",  # red
#   "#8b1a1a",  # dark red
#   "#6b1010",  # deeper red
#   "#4a0c0c",  # very dark red
#   "#691814",  # dark maroon
#   "#87241d",  # dark brick red
#   "#a63025",  # brick red
#   "#c43c2d",  # red-orange
#   "#e06830",  # orange
#   "#f0a030",  # golden orange
#   "#f8d040",  # yellow-orange
#   "#fff06a",  # bright yellow
#   "#c8f0ff",  # light ice blue
#   "#7ecbff",  # blue
#   "#3a8fd4",  # medium blue
#   "#1a5a9e",  # dark blue
#   "#0e3a6e",  # deep blue
#   "#061a3a",  # very dark blue
#   "#000000"   # black (extreme peaks)
# )

# Monotonic warm ramp: dark red -> bright yellow (no double-red visit,
# no dark-blue extreme). Low values fade into the dark basemap; hotspots pop.
no2_colors <- c(
  "#3a0808",  # very dark red (start)
  #"#440a0a",  # very dark red
  "#4e0b0b",  # very dark red
  #"#570d0d",  # dark red
  "#610e0e",  # dark red
  #"#6b1010",  # dark red
  "#771313",  # deep red
  "#821616",  # deep red
  "#8e1a1a",  # red
  "#991d1d",  # red
  "#a52020",  # red
  "#b22828",  # red
  "#bf3030",  # red
  "#cc3838",  # bright red
  "#d94040",  # bright red
  "#db4d3b",  # red-orange
  "#de5b35",  # red-orange
  "#e06830",  # orange
  "#e47630",  # orange
  "#e88430",  # orange
  "#ec9230",  # orange
  "#f0a030",  # golden orange
  "#f2a836",  # golden orange
  "#f3b03c",  # golden orange
  "#f5b841",  # yellow-orange
  "#f6c047",  # yellow-orange
  "#f8c84d",  # yellow-orange
  "#f9d053",  # yellow
  "#fbd859",  # yellow
  "#fce05e",  # yellow
  "#fee864",  # yellow
  "#fff06a",  # bright yellow (end of warm ramp)
  "#f4f088",  # pale yellow
  "#e9f0a6",  # yellow-green
  "#def0c4",  # pale mint
  "#d3f0e1",  # pale cyan
  "#c8f0ff",  # light ice blue
  "#7ecbff",  # blue
  "#3a8fd4",  # medium blue
  "#1a5a9e",  # dark blue
  "#0e3a6e",  # deep blue
  "#061a3a",  # very dark blue
  "#000000"   # black (extreme peaks)
)

no2_colors <- c(
  "#3a0808",  # very dark red (start)
  "#4e0b0b",  # very dark red
  "#771313",  # deep red
  "#821616",  # deep red
  "#991d1d",  # red
  "#a52020",  # red
  "#d94040",  # bright red
  "#db4d3b",  # red-orange
  "#e06830",  # orange
  "#e47630",  # orange
  "#f2a836",  # golden orange
  "#f5b841",  # yellow-orange
  "#f6c047",  # yellow-orange
  "#f9d053",  # yellow
  "#fbd859",  # yellow
  "#fce05e",  # yellow
  "#fee864",  # yellow
  "#fff06a",  # bright yellow (end of warm ramp)
  "#f4f088",  # pale yellow
  "#e9f0a6",  # yellow-green
  "#def0c4",  # pale mint
  "#c8f0ff",  # light ice blue
  "#7ecbff",  # blue
  "#3a8fd4",  # medium blue
  "#1a5a9e",  # dark blue
  "#17508c",  # darkening blue
  "#14467b",  # darker blue
  "#113c69",  # deep blue
  "#0e3258",  # very deep blue
  "#0c2846",  # very dark blue
  "#091e35",  # near-black blue
  "#061423",  # almost black
  "#030a12",  # barely blue
  "#000000"   # black (extreme peaks)
)

# Warm ramp -> dark purple variant (dark red -> orange -> yellow -> purple)
no2_colors <- c(
  "#3a0808",  # very dark red (start)
  "#4e0b0b",  # very dark red
  "#771313",  # deep red
  "#821616",  # deep red
  "#991d1d",  # red
  "#a52020",  # red
  "#d94040",  # bright red
  "#db4d3b",  # red-orange
  "#e06830",  # orange
  "#e47630",  # orange
  "#f2a836",  # golden orange
  "#f5b841",  # yellow-orange
  "#f6c047",  # yellow-orange
  "#f9d053",  # yellow
  "#fbd859",  # yellow
  "#fce05e",  # yellow
  "#fee864",  # yellow
  "#fff06a",  # bright yellow (end of warm ramp)
  "#f0d47a",  # muted yellow
  "#e0b58a",  # warm tan
  "#cf9599",  # muted pink
  "#bf75a8",  # dusty pink-purple
  "#a85eb0",  # light purple
  "#8b4aa3",  # purple
  "#723c8b",  # medium purple
  "#5b2f72",  # darker purple
  "#4a285e",  # deep purple
  "#3b214a",  # very deep purple
  "#2d1937",  # dark purple
  "#211127",  # near-black purple
  "#170a1a",  # almost black
  "#0c050e",  # barely purple
  "#000000"   # black (extreme peaks)
)

# Write GDAL color relief file (maps NO2 values directly to RGBA)
color_rgb <- col2rgb(no2_colors)
breaks <- seq(scale_min, scale_max, length.out = length(no2_colors))

# Alpha ramp: fade from transparent to fully opaque across the bottom of the scale
# so clean/low-NO2 areas show the basemap through. fade_in_steps counts how many
# color slots span the 0->opaque transition. Set to 1 to disable (all opaque).
fade_in_steps <- 5
alpha_values <- pmin(255L, as.integer(round(
  (seq_along(no2_colors) - 1) / max(1, fade_in_steps - 1) * 255
)))

color_file <- file.path(tmp_dir, "no2_colors.txt")
writeLines(c(
  "nv 0 0 0 0",
  sprintf("%.2f %d %d %d %d", breaks,
          color_rgb[1, ], color_rgb[2, ], color_rgb[3, ], alpha_values),
  # Clamp everything above scale_max to the last color, fully opaque
  sprintf("%.2f %d %d %d 255", 9999, color_rgb[1, length(no2_colors)],
          color_rgb[2, length(no2_colors)], color_rgb[3, length(no2_colors)])
), color_file)

# --- Find monthly files ---
tif_files <- sort(list.files(input_dir, pattern = "^no2_monthly_.*\\.tif$", full.names = TRUE))
tif_files <- tif_files[!grepl("\\.aux\\.xml", tif_files)]

if (length(tif_files) == 0) {
  stop("No .tif files found in ", input_dir, ". Run download.R first.")
}

# Parallel list of per-month weight files. Pair by filename date so an order
# mismatch or missing weight file is caught early rather than silently
# producing a wrong weighted mean.
weight_files <- file.path(dirname(tif_files),
                          sub("^no2_monthly_", "no2weight_", basename(tif_files)))
missing_w <- !file.exists(weight_files)
if (any(missing_w)) {
  stop("Missing NO2_WEIGHT files for: ",
       paste(basename(tif_files[missing_w]), collapse = ", "),
       ". Re-run download.R.")
}

# Extract YYYY-MM from filenames (expects date like 20260101 in filename)
dates <- regmatches(basename(tif_files), regexpr("\\d{8}", basename(tif_files)))
month_labels <- paste0(substr(dates, 1, 4), "-", substr(dates, 5, 6))

cat("Found", length(tif_files), "monthly files:\n")
cat(paste(" ", month_labels, "->", basename(tif_files)), sep = "\n")

if (inspect_scale) {
  cat("\nInspecting data distribution (this may take a minute)...\n")
  q99 <- sapply(tif_files, function(f) {
    global(rast(f), fun = quantile, probs = 0.99, na.rm = TRUE)[[1]]
  })
  cat(sprintf("Per-file 99th percentile - median: %.1f, max: %.1f\n",
              median(q99, na.rm = TRUE), max(q99, na.rm = TRUE)))
  cat(sprintf("Suggested scale_max: ~%d (currently %d)\n",
              ceiling(median(q99, na.rm = TRUE) / 10) * 10, scale_max))
  cat("Update `scale_max` above and re-run to apply.\n\n")
}

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
    cat("  Weighted rolling mean over", length(in_window), "months:",
        paste(month_labels[in_window], collapse = ", "), "\n")
    # Weighted mean: sum(no2 * w) / sum(w), using the L3 product's own
    # NO2_WEIGHT band. Pixels with little/no L2 coverage (e.g. polar night)
    # contribute near-zero weight and stop dominating the mean.
    no2_stack <- rast(lapply(tif_files[in_window], rast))
    w_stack   <- rast(lapply(weight_files[in_window], rast))
    # Zero out weight where NO2 is NA so num and den stay consistent.
    w_stack <- mask(w_stack, no2_stack, updatevalue = 0)
    num <- sum(no2_stack * w_stack, na.rm = TRUE)
    den <- sum(w_stack, na.rm = TRUE)
    r <- ifel(den > 0, num / den, NA)
    rm(no2_stack, w_stack, num, den)
    gc(verbose = FALSE)
  } else {
    # Monthly mode: drop pixels with near-zero gridding weight to suppress
    # spurious winter retrievals at high latitudes.
    r <- rast(tif_files[i])
    w <- rast(weight_files[i])
    r <- mask(r, w, maskvalues = c(NA, 0))
    rm(w)
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
  # ZOOM_LEVEL_STRATEGY=LOWER avoids upsampling the source; LANCZOS is the best
  # resampling filter for color imagery (sharper than AVERAGE at zoom transitions)
  mbt_path <- file.path(tmp_dir, paste0("no2_", month_label, ".mbtiles"))
  gdal_cmd <- sprintf(
    'gdal_translate -of MBTiles -co "TILE_FORMAT=WEBP" -co "QUALITY=100" -co "RESAMPLING=AVERAGE" -co "ZOOM_LEVEL_STRATEGY=UPPER" "%s" "%s"',
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
  # Clear any terra spill files left over from this iteration. tmpFiles() throws
  # if there are no orphans to remove, so swallow that — it just means nothing to do.
  tryCatch(
    terra::tmpFiles(current = FALSE, orphan = TRUE, remove = TRUE),
    error = function(e) invisible(NULL)
  )
  gc(verbose = FALSE)
}

# Clean up tmp directory
unlink(tmp_dir, recursive = TRUE)

# Write metadata
meta_path <- file.path(output_dir, "metadata.json")
writeLines(toJSON(metadata, auto_unbox = TRUE, pretty = TRUE), meta_path)
cat("\nMetadata written to:", meta_path, "\n")
cat("Done! Generated", length(tif_files), "monthly PMTiles.\n")
