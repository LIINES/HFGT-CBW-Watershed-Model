import geopandas as gpd
from shapely.geometry import MultiPolygon
from pathlib import Path
import zipfile
from concurrent.futures import ThreadPoolExecutor

# Load the shapefile
gdf = gpd.read_file('0-Data/1-RawData/0-GIS/QGIS/P6Beta_v3_LRSegs_081516.zip')

# Confirm attribute names
print("Columns in the shapefile:", gdf.columns.tolist())

# Convert geometries to MultiPolygon (vectorized approach)
def convert_to_multipolygon(geometry):
    if geometry.geom_type == 'Polygon':
        return MultiPolygon([geometry])
    elif geometry.geom_type == 'MultiPolygon':
        return geometry
    raise ValueError(f"Unsupported geometry type: {geometry.geom_type}")

gdf['geometry'] = gdf['geometry'].apply(convert_to_multipolygon)

# Select relevant columns and dissolve by grouping field
def create_dissolved_gdf(gdf, group_field):
    selected = gdf[[group_field, 'geometry', 'Acres']]
    return selected.dissolve(by=group_field, aggfunc='sum')

countyGDF = create_dissolved_gdf(gdf, 'FIPS_NHL')
riverSegGDF = create_dissolved_gdf(gdf, 'RiverSeg')
watershedGDF = create_dissolved_gdf(gdf, 'Watershed')

# Save shapefiles to folders
def save_shapefile(gdf, folder_path, filename):
    Path(folder_path).mkdir(parents=True, exist_ok=True)
    gdf.to_file(Path(folder_path) / filename)

save_shapefile(countyGDF, "0-Data/1-RawData/0-GIS/QGIS/Counties", "CountyLayer.shp")
save_shapefile(riverSegGDF, "0-Data/1-RawData/0-GIS/QGIS/RiverSegments", "RiverSegmentLayer.shp")
save_shapefile(watershedGDF, "0-Data/1-RawData/0-GIS/QGIS/Watersheds", "WatershedLayer.shp")

print("Shapefiles successfully created!")

# Zip folder function
def zip_folder(folder_path, zip_file_path):
    with zipfile.ZipFile(zip_file_path, 'w', zipfile.ZIP_DEFLATED) as zip_file:
        for root, _, files in os.walk(folder_path):
            for file in files:
                file_path = Path(root) / file
                zip_file.write(file_path, file_path.relative_to(folder_path))

# Output folder setup
output_folder = Path("0-Data/1-RawData/0-GIS/QGIS/ZippedPolygons")
output_folder.mkdir(parents=True, exist_ok=True)

# Zipping folders in parallel
folders_to_zip = [
    ("0-Data/1-RawData/0-GIS/QGIS/Counties", output_folder / 'County.zip'),
    ("0-Data/1-RawData/0-GIS/QGIS/RiverSegments", output_folder / 'RiverSeg.zip'),
    ("0-Data/1-RawData/0-GIS/QGIS/Watersheds", output_folder / 'Watershed.zip'),
]

with ThreadPoolExecutor() as executor:
    executor.map(lambda args: zip_folder(*args), folders_to_zip)

print("Folders zipped successfully!")


# # Plotting Counties
# fig1, ax1 = plt.subplots(figsize=(12, 10))
# countyGDF.plot(ax=ax1, color='lightgreen', edgecolor='black', alpha=0.5)
# ax1.set_title('Counties', fontsize=15)
# ax1.set_xlabel('Longitude', fontsize=12)
# ax1.set_ylabel('Latitude', fontsize=12)
# plt.show()
#
# # Plotting River Segments
# fig2, ax2 = plt.subplots(figsize=(12, 10))
# riverSegGDF.plot(ax=ax2, color='lightblue', edgecolor='black', alpha=0.5)
# ax2.set_title('RiverSegments', fontsize=15)
# ax2.set_xlabel('Longitude', fontsize=12)
# ax2.set_ylabel('Latitude', fontsize=12)
# plt.show()
#
# # Plotting Watersheds
# fig3, ax3 = plt.subplots(figsize=(12, 10))
# watershedGDF.plot(ax=ax3, color='blue', edgecolor='black', alpha=0.5)
# ax2.set_title('Watersheds', fontsize=15)
# ax2.set_xlabel('Longitude', fontsize=12)
# ax2.set_ylabel('Latitude', fontsize=12)
# plt.show()
#
# # Plotting Land River Segments
# fig4, ax4 = plt.subplots(figsize=(12, 10))
# gdf.plot(ax=ax4, color='orange', edgecolor='black', alpha=0.5)
# ax2.set_title('Land-River Segments', fontsize=15)
# ax2.set_xlabel('Longitude', fontsize=12)
# ax2.set_ylabel('Latitude', fontsize=12)
# plt.show()
