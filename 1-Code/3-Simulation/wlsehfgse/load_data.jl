# File name load_data.jl
# Purpose: loads CAST scenario and source data, myLFES data, and GIS data
# Megan Harris

using Pkg
Pkg.develop(path="1-Code/3-Simulation/wlsehfgse/HFNMCFTools")
using HFNMCFTools
using PrettyPrint
using DataFrames, XLSX

### 0) Inputs ###
const BASE_FOLDER   = "0-Data/1-RawData/1-ScenarioData/2024-progress"
const PATH_LOADS    = joinpath(BASE_FOLDER, "loads-report-countyLoadSourceAgency.xlsx")
const SHEET_LOADS   = "Source - Agency"
const PATH_APPLIED  = joinpath(BASE_FOLDER, "nutrients-applied-county.xlsx")
const SHEET_APPLIED = "Nutrients Applied"
const PATH_DFACTOR  = "0-Data/1-RawData/2-SourceData/SourceDataRepaired.xlsx"
const SHEET_DFACTOR = "Delivery Factors"
const PATH_BASECOND  = "0-Data/1-RawData/1-ScenarioData/2024-progress/base-conditions-county.xlsx"
const SHEET_BASECOND = "Land Use Acres"

### 1) Load Data ###
norm_county(x) = replace(strip(String(x)), "(CBWS Portion Only)" => "") |> strip
norm_sector(s) = startswith(lowercase(String(s)), "agri") ? "Agriculture" :
                 startswith(lowercase(String(s)), "dev")  ? "Developed"   : String(s)
norm_lrs(l) = replace(strip(String(l)), "(CBWS)" => "") |> strip

# Excel files from CAST
loads_df   = DataFrame(XLSX.readtable(PATH_LOADS, SHEET_LOADS))
applied_df = DataFrame(XLSX.readtable(PATH_APPLIED, SHEET_APPLIED))
dfact_df   = DataFrame(XLSX.readtable(PATH_DFACTOR, SHEET_DFACTOR))
basecond_df = DataFrame(XLSX.readtable(PATH_BASECOND, SHEET_BASECOND))

rename!(loads_df, Dict(Symbol("Geography")=>:County))
rename!(applied_df, Dict(:Fips=>:FIPS, :Geography=>:County))
loads_df.County   = norm_county.(loads_df.County)
applied_df.County = norm_county.(applied_df.County)
applied_df.Sector = norm_sector.(applied_df.Sector)
basecond_df.LandRiverSegment = norm_lrs.(basecond_df.LandRiverSegment)

# Read LFES
# inputJSONFilePath = "0-Data/2-IntermediateData/jsonFiles/myLFES-ElectricPowerSystem-Defaultxml-Dynamiceconomicdispatch-2026-02-02-NoGit.json"
inputJSONFilePath = "0-Data/2-IntermediateData/jsonFiles/myLFES-ChesapeakeBayWatershedSystem-Defaultxml-Nitrogenphosphorusdelivery-2026-02-02-NoGit.json"
myLFES = HFNMCFTools.loadHFNMCFData(inputJSONFilePath)
# include("../../2-testFlowNetwork/extractHDF5/run_extractHDF5.jl")
# hdf5_filepath = "0-Data/2-IntermediateData/hdf5Files/myLFES-Mini-Chesapeake Bay System-Default-Nitrogen And Phosphorus-2.hdf5"
# myLFES = load_lfes_from_hdf5(hdf5_filepath)

# Shift to 1 based indices for julia
myLFES.systemConcept.idxPsiCapability .+= 1
myLFES.systemConcept.idxProcess .+= 1
myLFES.systemConcept.idxResource .+= 1
myLFES.physicalResource.idxResource .+= 1
myLFES.transformationResource.idxResource .+= 1
myLFES.transportProcess.idxOrigin .+= 1
myLFES.transportProcess.idxDestination .+= 1
myLFES.transportProcess.idxProcess .+= 1

# # Shapefiles from CAST
segments_shapefile = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/CentroidsSavedLRsegments.shp"
outlet_points_shapefile = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/OutletPointsWithCoordinates/OutletPointsWithCoordinates.shp"
outlet_lines_shapefile  = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/outletLinesNewRenamed.shp"
outlet_lines_estuary_shapefile = "0-Data/1-RawData/0-GIS/QGIS/OutletLinesNew/OutletLinesEstuaryNew/OutletLinesEstuaryNew.shp"
estuary_shapefile_zip = "0-Data/1-RawData/0-GIS/QGIS/Coastline/Chesapeake_Bay_Shoreline_High_Resolution.zip"  # (see note below)