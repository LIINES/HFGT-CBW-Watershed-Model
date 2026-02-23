import geopandas as gpd
import pandas as pd
from write_WaterOnly_xml import writeWaterOnlyXMLfromGDF

# Define the paths to the input shapefiles
segments_shapefile = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/CentroidsSavedLRsegments.shp"
outlet_points_shapefile = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/OutletPointsWithCoordinates/OutletPointsWithCoordinates.shp"
outlet_lines_shapefile = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/outletLinesNewRenamed.shp"
outlet_lines_estuary_shapefile = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/OutletLinesEstuaryNew/OutletLinesEstuaryNew.shp"
estuary_shapefile = "0-Data/1-RawData/0-GIS/QGIS/Coastline/Chesapeake_Bay_Shoreline_High_Resolution.zip"

# Load the shapefiles as GeoDataFrames
gdf_segments = gpd.read_file(segments_shapefile)
gdf_outlet_points = gpd.read_file(outlet_points_shapefile)
gdf_outlet_lines = gpd.read_file(outlet_lines_shapefile)
gdf_outlet_lines_estuary = gpd.read_file(outlet_lines_estuary_shapefile)
gdf_estuary = gpd.read_file(estuary_shapefile)

# Define the configuration dictionary
config = {
    "systemName": "Chesapeake Bay System",
    "scenario": "Water Only Scenario",
    "refArchitecture":"Watershed System",
    "dataState":"raw",
    "inputDataFormat":"default",
    "version": "4.2.3",
    "verboseMode": "false",
    "outputFileType": "hdf5",
    "analysisMethod":"default",
    "outputDataFormat":"Mini",
    "outputFileType":"hdf5",
    "simHorizon": "2",
    "deltaT": "2"
}

# Define the output XML file path
output_file = "0-Data/2-IntermediateData/xmlFiles/chesapeake_bay_system_waterOnly.xml"

# Call the function to generate the XML
writeWaterOnlyXMLfromGDF(
    gdf_segments=gdf_segments,
    gdf_outlet_points=gdf_outlet_points,
    gdf_outlet_lines=gdf_outlet_lines,
    gdf_outlet_lines_estuary=gdf_outlet_lines_estuary,
    gdf_estuary=gdf_estuary,
    outputFile=output_file,
    config=config
)