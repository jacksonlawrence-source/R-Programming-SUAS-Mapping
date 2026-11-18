# Rank one grid-sampled landing footprint per visually mapped surface.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 9L) {
  stop(
    paste(
      "Usage: Rscript 03_rank_landing_zones.R <orthophoto.tif> <surfaces> <obstacles>",
      "<longitude> <latitude> <footprint_m> <clearance_m> <grid_m> <output_dir>"
    ),
    call. = FALSE
  )
}
if (!requireNamespace("terra", quietly = TRUE)) {
  stop("Install the R package 'terra' before running this script.", call. = FALSE)
}

inputs <- args[1:3]
missing_input <- inputs[!file.exists(inputs)]
if (length(missing_input)) {
  stop("Input file not found: ", paste(missing_input, collapse = ", "), call. = FALSE)
}
parameters <- suppressWarnings(as.numeric(args[4:8]))
coordinates <- parameters[1:2]
footprint_m <- parameters[3]
clearance_m <- parameters[4]
grid_m <- parameters[5]
output_dir <- args[9]
if (any(!is.finite(parameters)) || any(abs(coordinates) > c(180, 90)) ||
    footprint_m <= 0 || clearance_m < 0 || grid_m <= 0) {
  stop(
    paste(
      "Supply WGS 84 longitude and latitude in decimal degrees and distances in metres.",
      "Footprint width and grid spacing must be positive. Clearance must be zero or greater."
    ),
    call. = FALSE
  )
}

orthophoto <- terra::rast(inputs[1])
band_count <- terra::nlyr(orthophoto)
map_crs <- terra::crs(orthophoto)
if (!band_count %in% c(3L, 4L) || !nzchar(map_crs) || terra::is.lonlat(orthophoto) ||
    !isTRUE(all.equal(terra::linearUnits(orthophoto), 1))) {
  stop("Use an RGB or RGBA WebODM GeoTIFF in a projected CRS with metre units.", call. = FALSE)
}

read_polygons <- function(path, label) {
  polygons <- terra::vect(path)
  if (nrow(polygons) == 0L || terra::geomtype(polygons) != "polygons" ||
      !nzchar(terra::crs(polygons))) {
    stop(label, " must contain georeferenced polygons.", call. = FALSE)
  }
  polygons <- terra::project(polygons, map_crs)
  if (!isTRUE(all(terra::is.valid(polygons)))) {
    stop(label, " contains invalid polygon geometry.", call. = FALSE)
  }
  polygons
}

surfaces <- read_polygons(inputs[2], "Suitable surfaces")
obstacles <- read_polygons(inputs[3], "Obstacles")
surface_ids <- surfaces$surface_id
if (is.null(surface_ids) || anyNA(surface_ids) || any(!nzchar(trimws(surface_ids))) ||
    anyDuplicated(surface_ids)) {
  stop("Suitable surfaces need unique, nonempty surface_id values.", call. = FALSE)
}

mannequin <- terra::vect(matrix(coordinates, nrow = 1), type = "points", crs = "EPSG:4326")
mannequin <- terra::project(mannequin, map_crs)
mannequin_xy <- terra::crds(mannequin)
if (nrow(mannequin_xy) != 1L || any(!is.finite(mannequin_xy))) {
  stop("The mannequin point could not be projected into the map CRS.", call. = FALSE)
}
mannequin_pixel <- terra::extract(orthophoto, mannequin, ID = FALSE)
if (anyNA(mannequin_pixel[1, 1:3]) ||
    (band_count == 4L && !isTRUE(mannequin_pixel[[4]][1] > 0))) {
  stop("The mannequin point falls outside the mapped footprint.", call. = FALSE)
}

half_width <- footprint_m / 2
alpha_band <- if (band_count == 4L) 4L else NULL
coverage <- if (is.null(alpha_band)) orthophoto else orthophoto[[alpha_band]]
map_extent <- as.vector(terra::ext(orthophoto))

screen_surface <- function(surface) {
  bounds <- as.vector(terra::ext(surface))
  xmin <- max(bounds[1], map_extent[1]) + half_width
  xmax <- min(bounds[2], map_extent[2]) - half_width
  ymin <- max(bounds[3], map_extent[3]) + half_width
  ymax <- min(bounds[4], map_extent[4]) - half_width
  if (xmin > xmax || ymin > ymax) {
    return(NULL)
  }

  grid <- expand.grid(
    x = unique(c(seq(xmin, xmax, by = grid_m), xmax)),
    y = unique(c(seq(ymin, ymax, by = grid_m), ymax))
  )
  west <- grid$x - half_width
  east <- grid$x + half_width
  south <- grid$y - half_width
  north <- grid$y + half_width
  footprints <- terra::vect(
    sprintf(
      "POLYGON ((%.10f %.10f, %.10f %.10f, %.10f %.10f, %.10f %.10f, %.10f %.10f))",
      west, south, east, south, east, north, west, north, west, south
    ),
    crs = map_crs
  )
  inside <- which(terra::is.related(footprints, surface, "coveredby"))
  if (!length(inside)) {
    return(NULL)
  }

  # Measure from the footprint edge to the nearest mapped obstacle.
  obstacle_distance <- apply(terra::distance(footprints[inside, ], obstacles), 1, min)
  clear <- which(obstacle_distance > 0 & obstacle_distance >= clearance_m)
  eligible <- inside[clear]
  target_distance <- sqrt(
    (grid$x[eligible] - mannequin_xy[1, 1])^2 + (grid$y[eligible] - mannequin_xy[1, 2])^2
  )
  for (candidate in order(target_distance, grid$x[eligible], grid$y[eligible])) {
    footprint <- footprints[eligible[candidate], ]
    # Check all overlapping source cells, including cells cut by the square edge.
    pixels <- terra::extract(coverage, footprint, fun = min, exact = TRUE, na.rm = FALSE, ID = FALSE)
    if (!anyNA(pixels) && (is.null(alpha_band) || isTRUE(pixels[[1]][1] > 0))) {
      footprint$surface_id <- surface$surface_id
      footprint$easting_m <- grid$x[eligible[candidate]]
      footprint$northing_m <- grid$y[eligible[candidate]]
      footprint$distance_to_mannequin_m <- target_distance[candidate]
      footprint$obstacle_clearance_m <- obstacle_distance[clear[candidate]]
      return(footprint)
    }
  }
  NULL
}

screened <- lapply(seq_len(nrow(surfaces)), function(i) screen_surface(surfaces[i, ]))
eligible <- Filter(Negate(is.null), screened)
results <- data.frame(
  rank = integer(), surface_id = character(), longitude = numeric(), latitude = numeric(),
  easting_m = numeric(), northing_m = numeric(), footprint_width_m = numeric(),
  distance_to_mannequin_m = numeric(), obstacle_clearance_m = numeric()
)
if (length(eligible)) {
  candidates <- do.call(rbind, eligible)
  candidates <- candidates[order(candidates$distance_to_mannequin_m, candidates$surface_id), ]
  centers <- cbind(candidates$easting_m, candidates$northing_m)
  candidate_points <- terra::vect(centers, type = "points", crs = map_crs)
  lonlat <- terra::crds(terra::project(candidate_points, "EPSG:4326"))
  results <- data.frame(
    rank = seq_len(nrow(candidates)), surface_id = candidates$surface_id,
    longitude = round(lonlat[, 1], 8), latitude = round(lonlat[, 2], 8),
    easting_m = round(centers[, 1], 3), northing_m = round(centers[, 2], 3),
    footprint_width_m = footprint_m,
    distance_to_mannequin_m = round(candidates$distance_to_mannequin_m, 3),
    obstacle_clearance_m = round(candidates$obstacle_clearance_m, 3)
  )
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
table_path <- file.path(output_dir, "landing-zone-candidates.csv")
map_path <- file.path(output_dir, "landing-zone-map.png")
write.csv(results, table_path, row.names = FALSE)
grDevices::png(map_path, width = 1600, height = 1060, res = 160)
tryCatch({
  terra::plotRGB(
    orthophoto, a = alpha_band, scale = 255, axes = TRUE, maxcell = 1200000,
    mar = c(4.5, 6, 4.5, 2), colNA = "white"
  )
  graphics::mtext("Landing-zone candidates", side = 3, line = 2.3, adj = 0, font = 2, cex = 1.5)
  graphics::mtext(
    sprintf("%g m square footprint, %g m minimum clearance", footprint_m, clearance_m),
    side = 3, line = 0.9, adj = 0, col = "#495663"
  )
  terra::plot(surfaces, add = TRUE, col = NA, border = "#75E0AA", lwd = 2)
  terra::plot(obstacles, add = TRUE, col = NA, border = "#F57B6C", lwd = 1.5)
  if (nrow(results)) {
    terra::plot(candidates, add = TRUE, col = "#72D4FA", border = "#17212B", lwd = 2)
    graphics::text(centers, labels = results$rank, col = "#17212B", font = 2, cex = 0.82)
  }
  graphics::points(mannequin_xy, pch = 21, bg = "#FBC044", col = "#17212B", cex = 1.5, lwd = 2)
  graphics::legend(
    "bottomright", c("Mannequin", "Screened surface", "Mapped obstacle", "Ranked footprint"),
    pch = c(21, NA, NA, 22), pt.bg = c("#FBC044", NA, NA, "#72D4FA"),
    lty = c(NA, 1, 1, NA), lwd = 2,
    col = c("#17212B", "#258058", "#B74136", "#17212B"),
    bg = "white", box.col = "#B9C2C9", cex = 0.75, inset = 0.015
  )
}, finally = invisible(grDevices::dev.off()))

message(sprintf("%d of %d surfaces yielded a candidate.", nrow(results), nrow(surfaces)))
message("Ranked table: ", table_path)
message("Annotated map: ", map_path)
