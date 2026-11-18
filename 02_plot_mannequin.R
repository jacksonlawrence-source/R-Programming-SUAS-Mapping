# Run from the project root with a WebODM RGB or RGBA GeoTIFF and a WGS 84 point.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
  stop(
    "Usage: Rscript 02_plot_mannequin.R <orthophoto.tif> <longitude> <latitude> <map.png>",
    call. = FALSE
  )
}

orthophoto_path <- args[1]
coordinates <- suppressWarnings(as.numeric(args[2:3]))
output_path <- args[4]
if (!file.exists(orthophoto_path)) {
  stop("Orthophoto file not found: ", orthophoto_path, call. = FALSE)
}
if (any(!is.finite(coordinates)) || any(abs(coordinates) > c(180, 90))) {
  stop("Use WGS 84 longitude and latitude in decimal degrees.", call. = FALSE)
}
if (!grepl("\\.png$", output_path, ignore.case = TRUE)) {
  stop("The output path must end in .png.", call. = FALSE)
}
if (!requireNamespace("terra", quietly = TRUE)) {
  stop("Install the R package 'terra' before running this script.", call. = FALSE)
}

orthophoto <- terra::rast(orthophoto_path)
band_count <- terra::nlyr(orthophoto)
if (!band_count %in% c(3L, 4L) || !nzchar(terra::crs(orthophoto))) {
  stop("Use a georeferenced WebODM GeoTIFF with RGB or RGBA bands.", call. = FALSE)
}

# Convert the supplied longitude and latitude to the orthophoto's map coordinates.
mannequin <- terra::vect(matrix(coordinates, nrow = 1), type = "points", crs = "EPSG:4326")
mannequin <- terra::project(mannequin, terra::crs(orthophoto))
map_xy <- terra::crds(mannequin)
if (nrow(map_xy) != 1L || any(!is.finite(map_xy))) {
  stop("The point could not be projected into the orthophoto's CRS.", call. = FALSE)
}

# The GeoTIFF extent can contain gaps. In a WebODM RGBA export, zero alpha marks
# unmapped cells even when the RGB bands contain numeric values.
pixel <- terra::extract(orthophoto, mannequin, ID = FALSE)
if (anyNA(pixel[1, 1:3]) || (band_count == 4L && !isTRUE(pixel[[4]][1] > 0))) {
  stop("The mannequin point falls outside the mapped footprint.", call. = FALSE)
}

alpha_band <- if (band_count == 4L) 4L else NULL
point_color <- "#FBC044"
dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)
grDevices::png(output_path, width = 1600, height = 1060, res = 160)
tryCatch({
  terra::plotRGB(
    orthophoto, a = alpha_band, scale = 255, axes = TRUE, maxcell = 1200000,
    mar = c(4.6, 6, 4.8, 2.2), colNA = "white"
  )
  graphics::mtext("Synthetic mannequin location", side = 3, line = 2.6, adj = 0,
                  font = 2, cex = 1.5)
  graphics::mtext("WebODM orthophoto", side = 3, line = 1.2, adj = 0, col = "#495663")
  graphics::mtext("Map X", side = 1, line = 2.6)
  graphics::mtext("Map Y", side = 2, line = 2.6, las = 0)
  graphics::points(map_xy, pch = 21, bg = point_color, col = "#17212B", cex = 1.9, lwd = 2)
  graphics::legend(
    "bottomright", "Synthetic mannequin", pch = 21, pt.bg = point_color,
    pt.cex = 1.4, bg = "white", box.col = "#B9C2C9", inset = 0.02
  )
}, finally = invisible(grDevices::dev.off()))

map_crs <- terra::crs(orthophoto, describe = TRUE)
message("Raster CRS: ", map_crs$name)
message(sprintf("Mannequin map coordinates: x %.3f, y %.3f", map_xy[1, 1], map_xy[1, 2]))
message("Map written to ", normalizePath(output_path, winslash = "/"))
