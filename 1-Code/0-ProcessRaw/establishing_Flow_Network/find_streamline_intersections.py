# Title: Find Streamline Intersections
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd
from shapely.ops import unary_union

# Define the target CRS for consistency across all files
target_crs = "EPSG:5070"  # NAD 1983 Albers Equal Area Conic

# Load and reproject the streamlines
print("Reading Streamlines File...")
streamlines = gpd.read_file("0-Data/1-RawData/0-GIS/QGIS/Streams/smooth_streams.zip")
print("Projecting Streamlines File...")
streamlines = streamlines.to_crs(target_crs)

# Load and reproject the polygon boundary lines
print("Reading polygonlines file...")
polygon_lines = gpd.read_file("0-Data/1-RawData/0-GIS/QGIS/RiverSegmentLines/RiverSegmentLines.shp")
print("Projecting polygonlines file...")
polygon_lines = polygon_lines.to_crs(target_crs)

# Initialize an empty list to collect intersection points
intersection_points = []

# Use unary_union to create a single, merged geometry for each set of lines
print("Creating unified geometry for streamlines...")
streamlines_union = unary_union(streamlines.geometry)
print("Creating unified geometry for polygon lines...")
polygon_lines_union = unary_union(polygon_lines.geometry)

# Find intersections and keep only points
print("Finding intersections of streamlines and polygonlines...")
intersection_result = streamlines_union.intersection(polygon_lines_union)

# Check if the result contains points
if intersection_result.geom_type == 'Point':
    intersection_points.append(intersection_result)
    print("Found an intersection point.")
elif intersection_result.geom_type == 'MultiPoint':
    intersection_points.extend(intersection_result.geoms)
    print(f"Found {len(intersection_result.geoms)} intersection points.")

# Convert the intersection points into a GeoDataFrame
print("Converting intersection points to GeoDataFrame...")
intersection_gdf = gpd.GeoDataFrame(geometry=intersection_points, crs=target_crs)

# Save to a new shapefile
print("Saving intersection points to a new shapefile...")
intersection_gdf.to_file("0-Data/1-RawData/0-GIS/QGIS/IntersectionPoints/intersection_points.shp")

print("Intersection points have been saved.")
