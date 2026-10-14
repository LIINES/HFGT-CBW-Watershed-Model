##############
# WLSEHFGSE for Watershed Systems
##############
using HDF5, XLSX, DataFrames, SparseArrays, LinearAlgebra, JuMP, Gurobi, StatsBase, Statistics

include("load_data.jl")
include("process_CAST_data.jl")
include("build_lrs_eos.jl")          # 2026-10: land-river-segment EOS/EOR loads
include("wlsehfgse_watershed.jl")

# include("../../4-Visualization/generate_maps.jl")