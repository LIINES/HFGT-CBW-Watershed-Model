##############
# WLSEHFGSE for Watershed Systems
##############
using HDF5, XLSX, DataFrames, SparseArrays, LinearAlgebra, JuMP, Gurobi, StatsBase, Statistics

include("load_data.jl")
include("process_CAST_data.jl")
include("wlsehfgse_watershed.jl")

# include("../../4-Visualization/generate_maps.jl")