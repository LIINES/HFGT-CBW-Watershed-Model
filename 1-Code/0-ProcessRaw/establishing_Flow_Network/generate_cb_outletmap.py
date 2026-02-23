import geopandas as gpd
import matplotlib.pyplot as plt
import os

# File paths
land_river_segments_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/CentroidsSavedLRsegments.shp"
new_outlet_points_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/OutletPointsWithCoordinates/OutletPointsWithCoordinates.shp"
river_line_connections_path = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/outletLinesNewRenamed.shp"
estuary_line_connections_path = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/OutletLinesEstuaryNew/OutletLinesEstuaryNew.shp"

# Output directory
output_dir = "0-Data/3-Output/Maps"
os.makedirs(output_dir, exist_ok=True)

# Load one layer to get CRS
crs_reference = gpd.read_file(land_river_segments_path).crs

# Load and reproject layers
land_river_segments = gpd.read_file(land_river_segments_path).to_crs(crs_reference)
new_outlet_points = gpd.read_file(new_outlet_points_path).to_crs(crs_reference)
river_line_connections = gpd.read_file(river_line_connections_path).to_crs(crs_reference)
estuary_line_connections = gpd.read_file(estuary_line_connections_path).to_crs(crs_reference)

# Create the figure and axis
fig, ax = plt.subplots(figsize=(10, 10))

# Plot each layer
land_river_segments.plot(ax=ax, color="#a8d5a2", edgecolor="black", label="Land-River Segments")
river_line_connections.plot(ax=ax, color="blue", linewidth=1, label="River Connections")
estuary_line_connections.plot(ax=ax, color="navy", linewidth=1, label="Estuary Connections")
new_outlet_points.plot(ax=ax, color="red", markersize=10, marker="o", label="New Outlet Points")

# Customize and save
ax.set_title("Land-River Segments with Outlet Points and Connections")
ax.axis("off")
ax.legend(loc="upper left")

output_path = os.path.join(output_dir, "combined_map_land_outlets_connections.png")
plt.savefig(output_path, bbox_inches='tight', dpi=300)
plt.close()

print(f"Map saved at {output_path}")