# Title: Find Accumulation Outlet Points
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd
import rasterio
import rasterio.mask
import numpy as np
from shapely.geometry import Point

# Load the river segments as a GeoDataFrame
print("Loading river segment polygons...")
river_segments = gpd.read_file("0-Data/1-RawData/0-GIS/QGIS/RiverSegments/RiverSegmentLayer.shp")
print(f"Loaded {len(river_segments)} river segment polygons.")
print("River segment CRS:", river_segments.crs, "\n")

# Load the flow accumulation raster
print("Loading flow accumulation raster...")
with rasterio.open("0-Data/1-RawData/0-GIS/QGIS/DEM/processed/flow_accumulation.tif") as src:
    print("Flow accumulation raster loaded.")
    print("Flow accumulation raster CRS:", src.crs, "\n")

    # Reproject river segments if CRS does not match the raster
    if river_segments.crs != src.crs:
        print("CRS mismatch detected. Reprojecting river segments...")
        river_segments = river_segments.to_crs(src.crs)
        print("Reprojection complete.\n")

        # Set up an empty list to store outlet points
        outlet_points = []

        for i, segment in river_segments.iterrows():
            print(f"Processing river segment {i + 1}/{len(river_segments)}...")

            try:
                # Mask the raster with the current polygon
                masked, transform = rasterio.mask.mask(src, [segment.geometry], crop=True)
                masked_data = masked[0]  # Get the first (and only) band

                # Find the maximum flow accumulation value and its location
                max_val = np.nanmax(masked_data)
                if np.isnan(max_val):
                    print("  No data found within this segment. Skipping...\n")
                    continue  # Skip if there is no data in this segment

                # Get the row, col index of the maximum value
                row, col = np.where(masked_data == max_val)
                print(f"  Maximum flow accumulation found: {max_val}")
                print(f"  Location in raster (row, col): ({row[0]}, {col[0]})")

                # Transform the row, col to geographical coordinates
                outlet_x, outlet_y = rasterio.transform.xy(transform, row[0], col[0])
                print(f"  Outlet coordinates: (x: {outlet_x}, y: {outlet_y})\n")

                # Store the outlet point as a GeoDataFrame
                outlet_points.append({
                    'geometry': Point(outlet_x, outlet_y),
                    'RiverSeg': segment['RiverSeg']
                })

            except ValueError as e:
                # Handle the case where the polygon does not overlap with the raster
                print(f"  Segment {i + 1} does not overlap with the raster. Skipping...\n")

# Convert outlet points to a GeoDataFrame
print("Creating GeoDataFrame of outlet points...")
outlet_points_gdf = gpd.GeoDataFrame(outlet_points, crs=river_segments.crs)

# Save to a file or display
output_path = "0-Data/1-RawData/0-GIS/QGIS/OutletPoints/outlet_points.shp"
outlet_points_gdf.to_file(output_path)
print(f"Outlet points saved to {output_path}")