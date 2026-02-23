import geopandas as gpd
import pandas as pd
from writeXML import writeXMLfromGDF

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
    "systemName": "ChesapeakeBayWatershedSystem",
    "scenario": "NitrogenPhosphorusDelivery",
    "refArchitecture":"WatershedSystem",
    "dataState":"raw",
    "inputDataFormat":"defaultXML",
    "version": "4.6.1",
    "verboseMode": "true",
    "analysisMethod":"HFNMCF",
    "outputFileType": "json",
    "optimizer": "gurobi",
    "simHorizon": "1",
    "deltaT": "1"
}

# Define the output XML file path
output_file = "0-Data/2-IntermediateData/xmlFiles/chesapeake_bay_26-01-25.xml"

# Call the function to generate the XML
writeXMLfromGDF(
    gdf_segments=gdf_segments,
    gdf_outlet_points=gdf_outlet_points,
    gdf_outlet_lines=gdf_outlet_lines,
    gdf_outlet_lines_estuary=gdf_outlet_lines_estuary,
    gdf_estuary=gdf_estuary,
    outputFile=output_file,
    config=config
)