# Helper to extract a scalar Int from HDF5
function read_scalar_int(file, path::String)
    return Int(read(file[path]))
end

# Extract COO matrix components from a group
function read_coo_matrix(f, basepath::String)
    coords = read(f[basepath * "/coords"])["value"]
    values = read(f[basepath * "/data"])["value"]
    shape = Tuple(Int.(read(f[basepath * "/myShape"])["value"]))
    return (coords = coords, values = values, shape = shape)
end

# Convert COO tuple to SparseMatrixCSC
function coo_to_sparse(coo_matrix)
    rows, cols = vec(coo_matrix.coords[1, :]), vec(coo_matrix.coords[2, :])
    return sparse(rows .+ 1, cols .+ 1, vec(coo_matrix.values), coo_matrix.shape...)
end