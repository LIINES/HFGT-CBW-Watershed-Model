# Helper: decode HDF5 dictionary of encoded string values
# function read_name_dict(f, basepath::String)::Vector{String}
#     raw_dict = read(f[basepath])
#     keys_sorted = sort(collect(keys(raw_dict)), by=x -> parse(Int, replace(x, "_"=>"")))
#     return [String(UInt8.(vec(read(raw_dict[key]["value"])))) for key in keys_sorted]
# end

function read_name_dict(f, basepath::String)::Vector{String}
    raw_dict = read(f[basepath])

    # Convert Set to Vector
    key_list = collect(keys(raw_dict))

    # Keep keys that look like "_00001", "_0001", etc.
    numeric_keys = filter(k -> occursin(r"^_\d+$", k), key_list)

    # Sort keys by their numeric suffix (after removing the "_")
    keys_sorted = sort(numeric_keys, by = k -> parse(Int, replace(k, "_" => "")))

    # Decode strings in sorted order
    return [String(UInt8.(vec(raw_dict[key]["value"]))) for key in keys_sorted]
end