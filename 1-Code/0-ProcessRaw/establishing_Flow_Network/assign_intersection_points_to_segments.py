# Title: Assign Intersection Points to Segments
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd

# File paths
polygons_path = "0-Data/1-RawData/0-GIS/QGIS/RiverSegments/RiverSegmentLayer.shp"
intersection_points_path = "0-Data/1-RawData/0-GIS/QGIS/IntersectionPoints/intersection_points.shp"
output_intersections_path = "0-Data/1-RawData/0-GIS/QGIS/IntersectionPoints/assigned_intersection_points.shp"

# Load GeoDataFrames
print("Loading data...")
polygons = gpd.read_file(polygons_path)
intersection_points = gpd.read_file(intersection_points_path)
print(f"Loaded {len(polygons)} river segment polygons.")
print(f"Loaded {len(intersection_points)} intersection points.")

# Ensure CRS consistency
print("Ensuring CRS consistency...")
common_crs = polygons.crs
intersection_points = intersection_points.to_crs(common_crs)
polygons = polygons.to_crs(common_crs)
print("CRS consistency ensured.")

# Add a unique identifier to intersection points (optional if they don't have one)
intersection_points['id'] = intersection_points.index
print("Added unique identifiers to intersection points.")

# Initialize a list to store updated intersection data
updated_intersections = []

# Loop through intersection points and find the intersecting river segments
print("Mapping intersection points to river segments...")
for idx, intersection in intersection_points.iterrows():
    intersection_geom = intersection.geometry
    intersecting_segments = []

    # Check each polygon to see if it intersects the current intersection point
    for _, polygon in polygons.iterrows():
        polygon_geom = polygon.geometry
        if intersection_geom.intersects(polygon_geom):
            intersecting_segments.append(polygon['RiverSeg'])

    # Add the intersecting segments as a new column in the intersection_points GeoDataFrame
    if intersecting_segments:  # Only update if there are any intersections
        intersection['intersecting_segments'] = intersecting_segments
        updated_intersections.append(intersection)

    if idx % 100 == 0:  # Print progress every 100 intersection points
        print(f"Processed {idx} intersection points...")

# Convert updated list to GeoDataFrame
updated_intersection_gdf = gpd.GeoDataFrame(updated_intersections, crs=intersection_points.crs)
print(f"Updated intersection GeoDataFrame created with {len(updated_intersection_gdf)} points.")

# Save the updated GeoDataFrame to a new shapefile
print(f"Saving updated intersection points to {output_intersections_path}...")
updated_intersection_gdf.to_file(output_intersections_path)

print(f"Updated intersection points saved to {output_intersections_path}.")
