using SparseArrays, HDF5, DataFrames

include("../extractHDF5/run_extractHDF5.jl")
hdf5_filepath = "0-Data/2-IntermediateData/hdf5Files/myLFES-Mini-Chesapeake Bay System-Default-Nitrogen And Phosphorus-2.hdf5"
myLFES = load_lfes_from_hdf5(hdf5_filepath)


function create_process_table(myLFES::LFES, processNumber)
    # Step 1: Filter for processes of certain type (idxCapabilityProcess == processNumber)
    process_mask = myLFES.idxCapabilityProcess .== processNumber
    
    # Step 2: Extract relevant data for accept water processes
    capability_names = myLFES.engSysNetTransitions[process_mask]
    capability_numbers = myLFES.idxCapability[process_mask]
    resource_capability_numbers = myLFES.idxCapabilityResource[process_mask]
    
    # Step 3: Get resource names by finding the position of each resource number in idxResource
    resource_names = String[]
    for res_num in resource_capability_numbers
        idx = findfirst(x -> x == res_num, myLFES.idxResource)
        if idx !== nothing
            push!(resource_names, myLFES.resourceName[idx])
        else
            push!(resource_names, "Unknown Resource")
        end
    end
    
    # Step 4: Create lookup dictionary for transformation resource data
    # Map from resource index to transformation resource data
    trans_resource_lookup = Dict{Int, Int}()
    for (i, resource_idx) in enumerate(myLFES.idxTransformationResourceResource)
        trans_resource_lookup[resource_idx] = i
    end
    
    # Step 5: Get transformation resource data where available
    river_segments = Vector{Union{String, Missing}}(undef, length(resource_capability_numbers))
    counties = Vector{Union{String, Missing}}(undef, length(resource_capability_numbers))
    states = Vector{Union{String, Missing}}(undef, length(resource_capability_numbers))
    
    for (i, resource_num) in enumerate(resource_capability_numbers)
        if haskey(trans_resource_lookup, resource_num)
            trans_idx = trans_resource_lookup[resource_num]
            river_segments[i] = myLFES.transformationResourceRiverSegment[trans_idx]
            counties[i] = myLFES.transformationResourceCounty[trans_idx]
            states[i] = myLFES.transformationResourceState[trans_idx]
        else
            river_segments[i] = missing
            counties[i] = missing
            states[i] = missing
        end
    end
    
    # Step 6: Create the final table
    return DataFrame(
        capability_name = capability_names,
        capability_number = capability_numbers,
        resource_number = resource_capability_numbers,
        resource_name = resource_names,
        river_segment = river_segments,
        county = counties,
        state = states
    )
end

process_tables = Dict{String, DataFrame}()
process_names = ["accept agricultural nitrogen", "accept agricultural phosphorous","accept developed nitrogen", "accept agricultural phosphorous"]

for (i, name) in enumerate(process_names)
    process_tables[name] = create_process_table(myLFES, i-1)  # i-1 because processes start at 0
end

# Check missing rows for all process types
for (name, table) in process_tables
    missing_rows = table[
        ismissing.(table.river_segment) .| 
        ismissing.(table.county) .| 
        ismissing.(table.state), :]
    
    println("=== $name processes - Missing geographic data ===")
    println("Found $(nrow(missing_rows)) rows with missing data")
    if nrow(missing_rows) > 0
        println(missing_rows)
    else
        println("No missing geographic data!")
    end
    println()
end