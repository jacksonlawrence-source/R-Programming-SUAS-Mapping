# Run from the repository root. The source is a project ID or a saved GeoTIFF.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% 11:12 || !args[1] %in% c("webodm", "saved")) {
  stop(
    paste(
      "Usage: Rscript 04_run_mapping.R <webodm|saved> <project_id|orthophoto.tif>",
      "<flight.zip> <surfaces> <obstacles> <longitude> <latitude>",
      "<footprint_m> <clearance_m> <grid_m> <output_dir> [test_boundary]"
    ),
    call. = FALSE
  )
}
mode <- args[1]
source <- args[2]
archive <- args[3]
output_dir <- args[11]
boundary_path <- args[12]
packages <- c("terra", "jsonlite", if (mode == "webodm") "curl")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop("Install required R packages: ", paste(missing, collapse = ", "), call. = FALSE)
}
inputs <- c(args[3:5], if (mode == "saved") source, if (!is.na(boundary_path)) boundary_path)
if (any(!file.exists(inputs) | dir.exists(inputs))) {
  stop("Input file not found: ", paste(inputs[!file.exists(inputs) | dir.exists(inputs)], collapse = ", "),
       call. = FALSE)
}
if (!grepl("\\.zip$", archive, ignore.case = TRUE)) {
  stop("Supply a flight ZIP archive.", call. = FALSE)
}
parameters <- suppressWarnings(as.numeric(args[6:10]))
if (any(!is.finite(parameters)) || any(abs(parameters[1:2]) > c(180, 90)) ||
    parameters[3] <= 0 || parameters[4] < 0 || parameters[5] <= 0) {
  stop("Supply valid WGS 84 coordinates and footprint, clearance, and grid distances in metres.",
       call. = FALSE)
}
if (file.exists(output_dir)) {
  stop("Choose a new output directory for this run.", call. = FALSE)
}

run_script <- function(script, input_args) {
  executable <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  status <- system2(executable, c(shQuote(script), shQuote(input_args)))
  if (status != 0L) {
    stop(script, " failed. See the message above.", call. = FALSE)
  }
}

get_orthophoto <- function(images, preset, project_id, output_dir) {
  if (!grepl("^[1-9][0-9]*$", project_id)) {
    stop("Supply a numeric WebODM project ID.", call. = FALSE)
  }
  base_url <- sub("/+$", "", Sys.getenv("WEBODM_URL", "http://127.0.0.1:29800"))
  if (!grepl("^http://(127\\.0\\.0\\.1|localhost)(:[0-9]+)?$", base_url) &&
      !grepl("^https://[a-zA-Z0-9.-]+(:[0-9]+)?$", base_url)) {
    stop("Set WEBODM_URL to a local HTTP or HTTPS WebODM origin.", call. = FALSE)
  }
  api <- paste0(base_url, "/api")
  token <- Sys.getenv("WEBODM_TOKEN")

  request <- function(path, form = NULL, download = NULL) {
    handle <- curl::new_handle(connecttimeout = 10, timeout = 180, followlocation = FALSE)
    if (nzchar(token)) {
      curl::handle_setheaders(handle, Authorization = paste("JWT", token))
    }
    if (!is.null(form)) {
      curl::handle_setform(handle, .list = form)
    }
    response <- if (is.null(download)) {
      curl::curl_fetch_memory(paste0(api, path), handle)
    } else {
      curl::curl_fetch_disk(paste0(api, path), download, handle)
    }
    if (response$status_code < 200 || response$status_code >= 300) {
      stop("WebODM HTTP ", response$status_code, " at ", path, ".", call. = FALSE)
    }
    if (is.null(download) && length(response$content)) {
      return(jsonlite::fromJSON(rawToChar(response$content), simplifyVector = FALSE))
    }
    invisible(NULL)
  }

  if (!nzchar(token)) {
    username <- Sys.getenv("WEBODM_USERNAME")
    password <- Sys.getenv("WEBODM_PASSWORD")
    if (!nzchar(username) || !nzchar(password)) {
      stop("Set WEBODM_TOKEN or WEBODM_USERNAME and WEBODM_PASSWORD before running live mode.",
           call. = FALSE)
    }
    login <- request("/token-auth/", list(username = username, password = password))
    if (!is.character(login$token) || length(login$token) != 1L || !nzchar(login$token)) {
      stop("WebODM did not return an authentication token.", call. = FALSE)
    }
    token <- login$token
  }

  tasks_path <- sprintf("/projects/%s/tasks/", project_id)
  options <- Map(function(name, value) list(name = name, value = value), names(preset), preset)
  task <- request(tasks_path, list(
    name = paste("R mapping", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    partial = "true",
    options = jsonlite::toJSON(unname(options), auto_unbox = TRUE)
  ))
  task_id <- as.character(task$id)
  if (length(task_id) != 1L || !grepl("^[a-fA-F0-9-]+$", task_id)) {
    stop("WebODM did not return a valid task ID.", call. = FALSE)
  }
  message("WebODM task: ", task_id)
  writeLines(task_id, file.path(output_dir, "webodm-task-id.txt"))
  task_path <- paste0(tasks_path, task_id, "/")

  batches <- split(images, ceiling(seq_along(images) / 20))
  for (i in seq_along(batches)) {
    files <- lapply(batches[[i]], curl::form_file, type = "image/jpeg")
    names(files) <- rep("images", length(files))
    request(paste0(task_path, "upload/"), files)
    message("Uploaded batch ", i, " of ", length(batches))
  }
  committed <- request(paste0(task_path, "commit/"), list(commit = "true"))
  if (!isTRUE(committed$images_count == length(images))) {
    stop("WebODM's committed image count differs from the flight manifest.", call. = FALSE)
  }

  deadline <- Sys.time() + 3600
  repeat {
    task <- request(task_path)
    if (isTRUE(task$status == 40)) {
      break
    }
    if (isTRUE(task$status %in% c(30, 50))) {
      stop("WebODM task ", task_id, " failed or was canceled. ", task$last_error, call. = FALSE)
    }
    if (Sys.time() >= deadline) {
      stop("Timed out waiting for WebODM task ", task_id, ".", call. = FALSE)
    }
    Sys.sleep(5)
  }
  if (!"orthophoto.tif" %in% unlist(task$available_assets)) {
    stop("The completed WebODM task has no orthophoto GeoTIFF.", call. = FALSE)
  }

  orthophoto_path <- file.path(output_dir, "orthophoto.tif")
  staging_path <- file.path(output_dir, "orthophoto-download.tif")
  on.exit(unlink(staging_path), add = TRUE)
  request(paste0(task_path, "download/orthophoto.tif"), download = staging_path)
  raster <- terra::rast(staging_path)
  if (!terra::nlyr(raster) %in% c(3L, 4L) || !nzchar(terra::crs(raster))) {
    stop("The downloaded asset is not a georeferenced RGB or RGBA orthophoto.", call. = FALSE)
  }
  if (!file.rename(staging_path, orthophoto_path)) {
    stop("Could not save the downloaded orthophoto.", call. = FALSE)
  }
  processing_ms <- task$processing_time
  list(
    path = orthophoto_path, task_id = task_id,
    processing_s = if (isTRUE(processing_ms >= 0)) processing_ms / 1000 else NA_real_
  )
}

measure_coverage <- function(path, boundary_path) {
  raster <- terra::rast(path)
  if (!terra::nlyr(raster) %in% c(3L, 4L) || !nzchar(terra::crs(raster)) ||
      terra::is.lonlat(raster) || !isTRUE(all.equal(terra::linearUnits(raster), 1))) {
    stop("Coverage requires a projected RGB or RGBA orthophoto with metre units.", call. = FALSE)
  }
  valid <- if (terra::nlyr(raster) == 4L) {
    raster[[4]] > 0
  } else {
    !is.na(raster[[1]]) & !is.na(raster[[2]]) & !is.na(raster[[3]])
  }
  if (!is.na(boundary_path)) {
    boundary <- terra::vect(boundary_path)
    if (nrow(boundary) != 1L || terra::geomtype(boundary) != "polygons" ||
        !nzchar(terra::crs(boundary)) || !isTRUE(all(terra::is.valid(boundary)))) {
      stop("Supply a single valid georeferenced polygon or multipolygon as the test boundary.",
           call. = FALSE)
    }
    boundary <- terra::project(boundary, terra::crs(raster))
    boundary_area <- terra::expanse(boundary, transform = FALSE)
    if (!isTRUE(is.finite(boundary_area) && boundary_area > 0)) {
      stop("The test boundary must have positive area.", call. = FALSE)
    }
    valid <- terra::mask(valid, boundary, touches = FALSE)
  }
  mapped_cells <- terra::global(valid, "sum", na.rm = TRUE)[1, 1]
  mapped_area <- if (is.finite(mapped_cells)) mapped_cells * prod(terra::res(raster)) else 0
  if (is.na(boundary_path)) {
    return(list(mapped_footprint_m2 = round(mapped_area, 2)))
  }
  list(
    boundary_file = basename(boundary_path),
    boundary_area_m2 = round(boundary_area, 2),
    mapped_within_boundary_m2 = round(mapped_area, 2),
    boundary_coverage_percent = round(100 * min(mapped_area / boundary_area, 1), 2)
  )
}

if (!dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)) {
  stop("Could not create the output directory.", call. = FALSE)
}

elapsed <- function() unname(proc.time()[["elapsed"]])
started <- elapsed()
run_script("01_prepare_images.R", archive)
manifest <- file.path("data", "raw", paste0(tools::file_path_sans_ext(basename(archive)), "_manifest.csv"))
images <- read.csv(manifest, stringsAsFactors = FALSE)$image_path
if (length(images) < 2L) {
  stop("The flight ZIP must contain at least two images.", call. = FALSE)
}
prepared <- elapsed()

preset <- if (mode == "webodm") jsonlite::read_json("config/webodm-sift-low.json") else NULL
orthophoto <- if (mode == "webodm") {
  get_orthophoto(images, preset, source, output_dir)
} else {
  list(path = normalizePath(source, winslash = "/", mustWork = TRUE))
}
map_ready <- elapsed()
coverage <- measure_coverage(orthophoto$path, boundary_path)
coverage_ready <- elapsed()
run_script("03_rank_landing_zones.R", c(orthophoto$path, args[4:10], output_dir))
finished <- elapsed()
candidates <- read.csv(file.path(output_dir, "landing-zone-candidates.csv"), stringsAsFactors = FALSE)

report <- list(
  orthophoto_source = mode,
  flight_archive = basename(archive),
  image_count = length(images),
  webodm_task_id = orthophoto$task_id,
  webodm_preset = preset,
  timings_s = list(
    prepare_images = round(prepared - started, 2),
    webodm_upload_queue_processing_and_download = if (mode == "webodm") round(map_ready - prepared, 2),
    webodm_processing = orthophoto$processing_s,
    measure_coverage = round(coverage_ready - map_ready, 2),
    screen_and_export = round(finished - coverage_ready, 2),
    run_through_map_and_csv = round(finished - started, 2)
  ),
  screening = list(
    footprint_width_m = parameters[3], minimum_clearance_m = parameters[4], grid_spacing_m = parameters[5]
  ),
  coverage = coverage,
  candidate_count = nrow(candidates),
  candidates = candidates
)
report_path <- file.path(output_dir, "run-report.json")
jsonlite::write_json(
  report, report_path, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null", null = "null"
)
message("Run report: ", report_path)
