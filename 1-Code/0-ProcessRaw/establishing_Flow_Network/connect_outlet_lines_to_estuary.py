# Title: Connect Outlet Lines to Estuary
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd
from shapely.geometry import LineString
from create_flow_lines_from_river_segment_ID import parse_riverseg

# Load the river segment polygons and outlet points
path_to_polygons = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/RenamedPolygons.shp"
path_to_outlet_points = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPoints/RenamedPoints.shp"
output_path = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/OutletLinesEstuaryNew/OutletLinesEstuaryNew.shp"
polygons = gpd.read_file(path_to_polygons)
outlet_points = gpd.read_file(path_to_outlet_points)

# Parse RiverSeg codes and filter for 0001 and 0000 segments
outlet_points['UpstreamID'], outlet_points['DownstreamID'] = zip(*outlet_points['RiverSeg'].apply(parse_riverseg))
points_0001 = outlet_points[outlet_points['DownstreamID'] == '0001']
points_0000 = outlet_points[outlet_points['DownstreamID'] == '0000']

# Associate points with polygons by joining on RiverSeg
points_with_polygons = points_0001.merge(polygons, on='RiverSeg', suffixes=('_point', '_polygon'))
points_0000_polygons = points_0000.merge(polygons, on='RiverSeg', suffixes=('_point', '_polygon'))

# Create an empty list to store the new connections
connections = []
unconnected_0001_points = []  # For tracking unconnected 0001 points

# Find the nearest adjacent 0000 polygon for each 0001 polygon
for i, point_0001 in points_with_polygons.iterrows():
    polygon_0001 = point_0001['geometry_polygon']

    # Ensure polygon_0001 is valid and non-null
    if polygon_0001 is None or not polygon_0001.is_valid:
        print(f"Skipping invalid or null polygon for RiverSeg {point_0001['RiverSeg']}")
        continue

    # Find polygons from points_0000_polygons that are touching polygon_0001
    adjacent_0000 = points_0000_polygons[points_0000_polygons['geometry_polygon'].apply(lambda poly: poly.touches(polygon_0001))]

    if not adjacent_0000.empty:
        # Find the nearest point within touching polygons
        nearest_0000_idx = adjacent_0000['geometry_point'].distance(point_0001['geometry_point']).idxmin()
        nearest_point_0000 = adjacent_0000.loc[nearest_0000_idx]

        # Create a line connection from the 0001 point to the nearest 0000 point
        line = LineString([point_0001['geometry_point'], nearest_point_0000['geometry_point']])
        connections.append({'geometry': line, 'from': point_0001['RiverSeg'], 'to': nearest_point_0000['RiverSeg']})
    else:
        # If no adjacent 0000 polygon is found, mark as unconnected
        unconnected_0001_points.append(point_0001['RiverSeg'])
        print(f"No adjacent 0000 found for 0001 segment {point_0001['RiverSeg']}")

# Convert connections to a GeoDataFrame
connections_gdf = gpd.GeoDataFrame(connections, crs=outlet_points.crs)

# Save to new shapefile
connections_gdf.to_file(output_path)

# Print any unconnected 0001 segments for review
if unconnected_0001_points:
    print("The following 0001 segments could not be connected to any 0000 segment:")
    for seg in unconnected_0001_points:
        print(seg)
else:
    print("All 0001 segments successfully connected to 0000 segments.")

print("Connections created and saved successfully.")
