# Title: Create Flow Lines from River Segment ID
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd
from shapely.geometry import LineString
import pandas as pd

# Load the outlet points shapefile
path_to_outlet_points = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPoints/RenamedPoints.shp"
output_path = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/outletLinesNewRenamed.shp"

outlet_points = gpd.read_file(path_to_outlet_points)

# Load the upstream CSV file for connection validation
path_to_upstream_csv = "0-Data/1-RawData/0-GIS/QGIS/UpstreamLines/upstreamLines.csv"
upstream_data = pd.read_csv(path_to_upstream_csv)

# Create a set of valid connections from the CSV
valid_connections = set(zip(upstream_data['UpStreamSeg'], upstream_data['RiverSegment']))

# Function to split RiverSeg code
def parse_riverseg(segment):
    upstream_id = segment[4:8]  # First four digits after prefix
    downstream_id = segment[9:13]  # Next four digits after first set
    return upstream_id, downstream_id

# Extract upstream and downstream IDs
outlet_points['UpstrmID'], outlet_points['DownstrmID'] = zip(*outlet_points['RiverSeg'].apply(parse_riverseg))

# Create an empty list to store line geometries and associated attributes
lines = []
invalid_connections = []

# Find matching points to create lines
for i, point in outlet_points.iterrows():
    downstream_matches = outlet_points[outlet_points['UpstrmID'] == point['DownstrmID']]
    if not downstream_matches.empty:
        # Create lines for matched downstream segments
        for _, downstream_point in downstream_matches.iterrows():
            from_seg = point['RiverSeg']
            to_seg = downstream_point['RiverSeg']

            # Check if the connection exists in the CSV
            if (from_seg, to_seg) not in valid_connections:
                invalid_connections.append((from_seg, to_seg))
            else:
                # Create line geometry and add to the list of lines
                line = LineString([point.geometry, downstream_point.geometry])
                lines.append({
                    'geometry': line,
                    'from': from_seg,
                    'to': to_seg,
                    'UpstrmID': from_seg,
                    'DownstrmID': to_seg
                })

# Convert lines to GeoDataFrame
lines_gdf = gpd.GeoDataFrame(lines, crs=outlet_points.crs)

# Save to a new shapefile
lines_gdf.to_file(output_path)

# Print any connections that are missing from the CSV
if invalid_connections:
    print("The following connections were created but are not in the CSV file:")
    for from_seg, to_seg in invalid_connections:
        print(f"Connection from {from_seg} to {to_seg}")
else:
    print("All created connections exist in the CSV file.")