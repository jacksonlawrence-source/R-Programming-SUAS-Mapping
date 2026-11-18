# Automated UAV Mapping and Landing-Zone Selection Using R

Build a reproducible workflow for AAV's SUAS 2027 mapping task. R prepares flight photos, coordinates WebODM processing, and turns the resulting orthophoto and a supplied mannequin location into an annotated map and ranked landing-zone candidates.

## Project status

- Prepared 372 Gremsy VIO JPEGs and an image inventory. [01_prepare_images.R](01_prepare_images.R) extracts JPEGs from a flight ZIP and writes the manifest. Run `Rscript 01_prepare_images.R <flight-zip>` from the project root.
- Selected [SIFT Low settings](config/webodm-sift-low.json) for incremental SfM with Fast Orthophoto enabled. The selected run used ODM 3.8.2, took 232.68 seconds in WebODM, registered 346 of 372 frames, and mapped 44,425 m². The settings file records the key options from that run for manual WebODM setup and future automation.
- Verified read access to local NodeODX job status and settings. The optional `Connect-NodeODX.ps1` and `Connect-WebODM.ps1` scripts assist with checking local services on Windows. Their setup stores credentials under the user's local app-data directory.

The SIFT benchmark used the same 372 images. Each row represents one run, and the footprint measures pixels mapped across the whole orthophoto.

| SIFT feature quality | WebODM time | Registered photos | Mapped footprint |
| --- | ---: | ---: | ---: |
| Lowest | 4:17 | 346 / 372 | 43,934 m² |
| Low (selected) | 3:53 | 346 / 372 | 44,425 m² |

## Reproduce the mannequin map

Install the R package with `install.packages("terra")`. Image preparation uses base R. The mapping and screening scripts use `terra` and were verified with R 4.6.1 and terra 1.9-50.

- **Flight imagery** comes from AAV's 372-image Gremsy VIO flight ZIP. The project copy is `drive-download-20261118T015500Z-1-001.zip`. The image-preparation script takes the path to the ZIP as its only argument.
- **Orthophoto** comes from AAV OneDrive under `SUAS MAPPING/WebODM Test Results`. Use the **Incremental – sift – Low quality – 3m 53s processing** run and its `odm_orthophoto/odm_orthophoto.tif` file. It has 6,237 by 3,447 pixels in WGS 84 / UTM Zone 17N (EPSG:32617). AAV OneDrive access is required for the test data. Before submitting, provide the instructor with an accessible copy or download links.

Run from the project root, replacing the path and coordinate placeholders with your inputs. Supply longitude first and latitude second, in WGS 84 decimal degrees. Choose a point inside the mapped footprint.

```sh
Rscript 02_plot_mannequin.R "path/to/odm_orthophoto.tif" LONGITUDE LATITUDE "outputs/mannequin-map.png"
```

The script projects the input into the map CRS, checks for mapped pixels at the point, and writes a PNG with the point labeled as synthetic. The demo run was verified against the selected SIFT Low GeoTIFF, including rejection of points in an unmapped gap or outside the image.

## Screen and rank landing-zone candidates

Trace plausible landing surfaces and visible obstacles as two separate polygon layers over the orthophoto. Export each layer as a georeferenced, single-layer GeoPackage or GeoJSON. Give each plausible surface a unique `surface_id`. Include the visible features that should be excluded from the landing footprint, such as water, trees, structures, or parked vehicles.

Run from the project root using a projected WebODM GeoTIFF with metre units. The three distances after longitude and latitude are the square footprint width, minimum obstacle clearance, and search-grid spacing, in metres.

```sh
Rscript 03_rank_landing_zones.R "path/to/odm_orthophoto.tif" "data/processed/demo-surfaces.gpkg" "data/processed/demo-obstacles.gpkg" LONGITUDE LATITUDE 10 3 2 "outputs/landing-zones"
```

R tests grid-aligned squares for full containment in the labeled surface and mapped pixels. It measures clearance from the square edge to the nearest mapped obstacle and keeps the valid square closest to the mannequin on each surface. A finer grid samples more positions. The output directory contains an annotated `landing-zone-map.png` and a `landing-zone-candidates.csv` with ranks, coordinates, distances, and clearances. A run with zero candidates writes a header-only CSV.

The SIFT Low demo used three manually traced surfaces, a 10 m square, 3 m of clearance, and a 2 m grid. Two surfaces yielded candidates. The south lawn ranked first at 5.83 m from the synthetic mannequin, followed by the west meadow at 105.82 m. The pond margin was too narrow. The demo parameters are for testing. The current analysis uses visible, manually mapped features and horizontal clearances. Terrain slope, surface condition, and obstacle heights still need separate validation. The demo annotation layers and outputs stay local with the flight data.

## Run the complete workflow

Install the additional R packages with `install.packages(c("jsonlite", "curl"))`. The runner calls the image-preparation and candidate-screening scripts and writes the map, ranked CSV, and `run-report.json` to a new output directory. Use surface and obstacle layers drawn for the same flight.

For a live run, start WebODM with a processing node available. Use the project ID from its project URL and set `WEBODM_TOKEN`, or set `WEBODM_USERNAME` and `WEBODM_PASSWORD` for a local project account. These can be set in an untracked `.Renviron` file. The runner defaults to `http://127.0.0.1:29800`. Set `WEBODM_URL` if your installation uses another local port or an HTTPS origin. The [WebODM task API](https://docs.webodm.org/api/task/) supplies the task status and downloadable orthophoto.

```sh
Rscript 04_run_mapping.R webodm PROJECT_ID "flight.zip" "surfaces.gpkg" "obstacles.gpkg" LONGITUDE LATITUDE 10 3 2 "outputs/live-run"
```

The live path submits the tracked SIFT Low settings, uploads the JPEGs in batches, waits for processing, and downloads the GeoTIFF. It writes the WebODM task ID when the task is created so you can inspect an interrupted run in WebODM.

For a class demo with a saved orthophoto, use the same flight ZIP and its exported GeoTIFF. Saved mode measures the preparation and R output stages and records the WebODM timing fields as null.

```sh
Rscript 04_run_mapping.R saved "odm_orthophoto.tif" "flight.zip" "surfaces.gpkg" "obstacles.gpkg" LONGITUDE LATITUDE 10 3 2 "outputs/saved-run" "test-boundary.gpkg"
```

The optional last argument in either mode is a single test-boundary polygon or multipolygon. The report gives coverage within that boundary using the centres of mapped pixels. Omit the boundary to report the whole mapped footprint.

The saved SIFT Low replay used the 372 JPEGs already extracted from the original flight archive. R exported two ranked candidates and measured **87.83%** coverage within a **49,500 m²** rectangular test boundary drawn for the demo. The live API sequence was exercised against a local mock service. A fresh WebODM stitch requires authenticated access to the local project.

## Class project milestones

1. **Complete.** Load the SIFT Low GeoTIFF in R, project a synthetic mannequin point, and export the annotated map.
2. **Complete for the class demo.** Screen manually traced surfaces and rank qualifying footprints by distance to the mannequin. Add a slope check if suitable elevation data become available.
3. **Runner implemented and saved-flight replay verified.** Rehearse one authenticated live run and record its full time to export.
4. Package the R scripts, figures, and presentation. Document the package setup and provide instructor-accessible download instructions for the flight ZIP and any required large data.

Real mannequin detection and an A8 Mini/HM30 field rehearsal are subsequent AAV milestones.

## Class deliverables

- **Complete organized `.R` scripts** covering data processing, analysis, and figure generation. Include required packages, data sources, and download or access information for large datasets.
- **Approximately 10-minute presentation** covering project motivation and why R, study area and data, methods, results and discussion with figures and tables, and conclusions including what you learned. The Dec 1 and Dec 3 live sessions require advance signup. The recorded option is uploaded to Canvas.
- **Approximately two minutes within the presentation for an R code walkthrough.** Show one meaningful section, explain what it does, why you wrote it that way, and how it supports the results. Describe one programming challenge or decision. The landing-zone screening and ranking code is a candidate for this segment.

## GitHub workflow

Track the R scripts, WebODM preset, setup and data access instructions, small figures and result tables, and presentation in the project repository. Keep local raw imagery, full-resolution GeoTIFFs, and machine-specific configuration out of version control. Record a shareable data source and exact input names here before submission.
