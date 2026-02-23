import geopandas as gpd
import rasterio
import matplotlib.pyplot as plt
import os

# File paths
land_river_segments_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/CentroidsSavedLRsegments.shp"
river_segments_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/RenamedPolygons.shp"
dem_raster_path = "0-Data/1-RawData/0-GIS/QGIS/DEM/output_SRTMGL1.tif"
accumulation_raster_path = "0-Data/1-RawData/0-GIS/QGIS/DEM/processed/flow_accumulation.tif"
initial_outflow_points_path = "0-Data/1-RawData/0-GIS/QGIS/OutletPoints/outlet_points.shp"
stream_network_path = "0-Data/1-RawData/0-GIS/QGIS/Streams/smooth_streams.zip"
intersection_points_path = "0-Data/1-RawData/0-GIS/QGIS/IntersectionPoints/intersection_points.shp"
new_outlet_points_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/OutletPointsWithCoordinates/OutletPointsWithCoordinates.shp"
river_line_connections_path = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/outletLinesNewRenamed.shp"
estuary_line_connections_path = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/OutletLinesEstuaryNew/OutletLinesEstuaryNew.shp"

# Output directory for maps
output_dir = "0-Data/3-Output/Maps"
os.makedirs(output_dir, exist_ok=True)

# Load GeoDataFrames
print("Loading shapefiles...")
river_segments = gpd.read_file(river_segments_path)
crs = river_segments.crs  # Use river segments CRS as reference

# Reproject all layers to match the river segments CRS
land_river_segments = gpd.read_file(land_river_segments_path).to_crs(crs)
initial_outflow_points = gpd.read_file(initial_outflow_points_path).to_crs(crs)
stream_network = gpd.read_file(stream_network_path).to_crs(crs)
intersection_points = gpd.read_file(intersection_points_path).to_crs(crs)
new_outlet_points = gpd.read_file(new_outlet_points_path).to_crs(crs)
river_line_connections = gpd.read_file(river_line_connections_path).to_crs(crs)
estuary_line_connections = gpd.read_file(estuary_line_connections_path).to_crs(crs)

# Define a function to plot rasters
def plot_raster(ax, raster_path, title):
    with rasterio.open(raster_path) as src:
        img = src.read(1)
        extent = [src.bounds.left, src.bounds.right, src.bounds.bottom, src.bounds.top]
        ax.imshow(img, extent=extent, cmap='terrain')
        ax.set_title(title)
        ax.axis("off")

# Define a function to plot GeoDataFrames
def plot_vector(ax, gdf, color, title, edgecolor='black', marker=None, markersize=None, linewidth=None, label=None):
    if marker:
        gdf.plot(ax=ax, color=color, marker=marker, markersize=markersize, label=label)
    else:
        gdf.plot(ax=ax, color=color, edgecolor=edgecolor, linewidth=linewidth, label=label)
    ax.set_title(title)
    ax.axis("off")

# Define cohesive style
style = {
    "river_segments": {"color": "#c2c2c2", "edgecolor": "black"},  # Muted gray
    "land_river_segments": {"color": "#a8d5a2", "edgecolor": "black"},  # Light muted green
    "outflow_points": {"color": "red", "marker": "o", "markersize": 5},  # Smaller outlet points
    "intersection_points": {"color": "orange", "marker": "x", "markersize": 5},  # Smaller intersection points
    "stream_network": {"color": "cyan", "edgecolor": "black", "linewidth": 0.5},  # Thinner stream lines
    "line_connections": {"color": "blue", "edgecolor": "blue"},  # Blue lines for connections
    "adjacent_0000": {"color": "yellow", "edgecolor": "black"},
    "adjacent_0001": {"color": "purple", "edgecolor": "black"},
}

# Generate and save all maps
map_titles = [
    "Land River Segments",
    "River Segments Alone",
    "DEM Raster",
    "Accumulation Raster",
    "Initial Outflow Points",
    "Stream Network over River Segments",
    "Intersections with River Segments",
    "New Outlet Points",
    "River Segments with Connections",
    "River Segments Adjacent to Estuary"
]

fig_funcs = [
    lambda ax: plot_vector(ax, land_river_segments, **style["land_river_segments"], title=map_titles[0]),
    lambda ax: plot_vector(ax, river_segments, **style["river_segments"], title=map_titles[1]),
    lambda ax: plot_raster(ax, dem_raster_path, title=map_titles[2]),  # Added DEM Raster map back
    lambda ax: plot_raster(ax, accumulation_raster_path, title=map_titles[3]),  # Added Accumulation Raster map back
    lambda ax: (
        plot_vector(ax, river_segments, **style["river_segments"], title=map_titles[4]),
        plot_vector(ax, initial_outflow_points, **style["outflow_points"], title=None)
    ),
    lambda ax: (
        plot_vector(ax, river_segments, **style["river_segments"], title=map_titles[5]),
        plot_vector(ax, stream_network, **style["stream_network"], title=None)
    ),
    lambda ax: (
        plot_vector(ax, river_segments, **style["river_segments"], title=map_titles[6]),
        plot_vector(ax, intersection_points, **style["intersection_points"], title=None)
    ),
    lambda ax: (
        plot_vector(ax, river_segments, **style["river_segments"], title=map_titles[7]),
        plot_vector(ax, new_outlet_points, **style["outflow_points"], title=None)
    ),
    lambda ax: (
        plot_vector(ax, river_segments, **style["river_segments"], title=map_titles[8]),
        plot_vector(ax, new_outlet_points, **style["outflow_points"], title=None),
        plot_vector(ax, river_line_connections, **style["line_connections"], title=None),
        plot_vector(ax, estuary_line_connections, **style["line_connections"], title=None)
    ),
    lambda ax: (
        plot_vector(ax, river_segments, **style["river_segments"], title=map_titles[9]),
        plot_vector(
            ax,
            river_segments[river_segments["RiverSeg"].str.endswith("0000")],
            **style["adjacent_0000"],
            title=None
        ),
        plot_vector(
            ax,
            river_segments[river_segments["RiverSeg"].str.endswith("0001")],
            **style["adjacent_0001"],
            title=None
        )
    )
]

for i, func in enumerate(fig_funcs):
    print(f"Generating map {i+1}/{len(fig_funcs)}: {map_titles[i]}...")
    fig, ax = plt.subplots(figsize=(8, 8))
    func(ax)
    map_filename = f"{output_dir}/{map_titles[i].replace(' ', '_').lower()}.png"
    plt.savefig(map_filename, bbox_inches='tight', dpi=300)
    plt.close(fig)
    print(f"Map saved: {map_filename}")

print(f"All maps saved in {output_dir}")