using SparseArrays, HDF5, JuMP, Gurobi, LinearAlgebra, Plots, DataFrames

println("Loading LFES system from HDF5...")
include("../extractHDF5/run_extractHDF5.jl")
# hdf5_filepath = "0-Data/2-IntermediateData/hdf5Files/myLFES-Mini-Chesapeake Bay System-Default-Base Scenario-2.hdf5"
# hdf5_filepath = "0-Data/2-IntermediateData/hdf5Files/myLFES-Mini-Chesapeake Bay System-Default-Water Only Scenario-2.hdf5"
hdf5_filepath = "0-Data/2-IntermediateData/hdf5Files/myLFES-Mini-Chesapeake Bay System-Default-Nitrogen And Phosphorus-2.hdf5"
myLFES = load_lfes_from_hdf5(hdf5_filepath)
println("LFES loaded.")

# Simulation parameters
simulationDuration = Int(50)
deltaT = Int(1)
numTimeSteps = Int(simulationDuration / deltaT)
println("Time steps: $numTimeSteps (deltaT = $deltaT)")

# Create optimization model
println("Initializing JuMP model...")
model = Model(Gurobi.Optimizer)

println("Creating variables...")
@variable(model, QB[1:myLFES.numBuffers * myLFES.numOperands, 1:numTimeSteps+1] >= 0)
@variable(model, UEPlus[1:myLFES.numCapabilities, 1:numTimeSteps] >= 0)
@variable(model, UEMinus[1:myLFES.numCapabilities, 1:numTimeSteps] >= 0)

# Initial buffer storage
println("Setting initial conditions...")
QBinitCond = 0*ones(myLFES.numBuffers * myLFES.numOperands)
# for (i, name) in enumerate(myLFES.engSysNetPlaces)
#     if !occursin("ZZ0_9999_9999", name)
#         QBinitCond[i] = 1.0
#     end
# end
@constraint(model, QB[:, 1] .== QBinitCond)

# Set accept water processes to 1 for the first time step to add water to land segments

# --- NEW: Set the four accept processes to 1 at t=1, else 0 ---
accept_names = [
    "accept agricultural nitrogen",
    "accept developed nitrogen",
    "accept agricultural phosphorus",
    "accept developed phosphorus",
]

# Case-insensitive match to be safe:
accept_cap_idxs = findall(name -> lowercase(name) in accept_names,
                          lowercase.(myLFES.engSysNetTransitions))

println("Identifying inflow capabilities (1 +1, 0 -1)...")

inflow_cap_idxs = []

for psi in 1:myLFES.numCapabilities
    col = myLFES.incMat[:, psi]
    num_pos_ones = count(x -> x == 1, col)
    num_neg_ones = count(x -> x == -1, col)

    if num_pos_ones == 1 && num_neg_ones == 0
        push!(inflow_cap_idxs, psi)
    end
end

println("Found $(length(inflow_cap_idxs)) inflow capabilities. Applying UEMinus[psi,1] = 1.0...")

# Set UEMinus = 1.0 at time step 1, and 0.0 for all other time steps
for psi in inflow_cap_idxs
    @constraint(model, UEMinus[psi, 1] == 1.0)
    for t in 2:numTimeSteps
        @constraint(model, UEMinus[psi, t] == 0.0)
    end
end

# println("Allowing UEMinus ≤ 1.0 for all capabilities...")
# for k in 1:numTimeSteps
#     for psi in 1:myLFES.numCapabilities
#         @constraint(model, UEMinus[psi, k] <= 1.0)
#     end
# end

# Fix UEMinus to be constant across time
# println("Fixing UEMinus to less than or equal to 1.0 for all capabilities and time steps...")
# for k in 1:numTimeSteps
#     for psi in 1:myLFES.numCapabilities
#         @constraint(model, UEMinus[psi, k] == 1.0)
#     end
# end

# Duration constraint (assuming duration = 0)
println("Enforcing UEPlus == UEMinus...")
for k in 1:numTimeSteps
    for psi in 1:myLFES.numCapabilities
        @constraint(model, UEPlus[psi, k] == UEMinus[psi, k])
    end
end

# Mass balance dynamics
println("Adding mass balance constraints over time...")
for k in 1:numTimeSteps
    @constraint(model,
        QB[:, k+1] .== QB[:, k] +
        myLFES.incMatPlus * UEPlus[:, k] * deltaT -
        myLFES.incMatMinus * UEMinus[:, k] * deltaT)
end

# println("Setting final condition on the estuary to collect all the added and initial water")
# @constraint(model, QB[end,end] .== length(inflow_cap_idxs) .+ sum(QBinitCond))


# Objective
println("Setting dummy objective (for solver feasibility)...")
@objective(model, Min, sum(QB[1:(myLFES.numBuffers-1),end])+ sum(QB[(myLFES.numBuffers+1):(myLFES.numBufferOperandPairs-1),end]))

# Solve the model
println("Solving optimization model...")
optimize!(model)

transport_cap_idxs = findall(name -> occursin("transport", name), myLFES.engSysNetTransitions)

println("Analyzing results...")
if termination_status(model) == MOI.OPTIMAL || termination_status(model) == MOI.TIME_LIMIT
    QB_end = value.(QB[:, end])
    threshold = 1e-6
    nonzero_indices = findall(x -> abs(x) > threshold, QB_end)

    println("Simulation complete. Status: ", termination_status(model))
    if isempty(nonzero_indices)
        println("No sinks detected! All buffers drained.")
    else
        println("Buffers with remaining mass (potential sinks):")
        for idx in nonzero_indices
            if idx != myLFES.numBuffers || idx != myLFES.numBufferOperandPairs  # Not the estuary
                buffer_name = myLFES.engSysNetPlaces[idx]
                println("Place $idx ($buffer_name) has QB = $(QB_end[idx])")
            else
                println("Estuary place $idx has QB = $(QB_end[idx])")
            end
        end
        
        # Calculate statistics excluding the estuary
        non_estuary_indices = [idx for idx in nonzero_indices if idx != myLFES.numBuffers || idx != myLFES.numBufferOperandPairs]
        numNonZeroQB = length(non_estuary_indices)
        emptyQB = (myLFES.numBufferOperandPairs - 1) - numNonZeroQB
        percent_nonzero_QB = numNonZeroQB/(myLFES.numBufferOperandPairs-1)*100
        println("Number of Not-Empty Buffer-Operand Pairs (excluding estuary): $numNonZeroQB")
        println("Number of Empty Buffer-Operand Pairs: $emptyQB")
        println("Percent Not-Empty Operand Pairs: $percent_nonzero_QB%")
    end
else
    println("Optimization failed with status: ", termination_status(model))
end

# Assume:
# - QB: solution matrix (numBuffers × numTimeSteps+1)
# - buffer_names: list of buffer names from myLFES.engSysNetPlaces
# - myLFES.numBufferOperandPairs: total number of buffer-operand pairs
# - estuary_idx: index of estuary buffer (e.g., last buffer)

# Define estuary index (last buffer-operand pair)
estuary_idx = myLFES.numBufferOperandPairs

# Extract values from JuMP variable
QB_matrix = value.(QB)

# Time vector
timesteps = 0:deltaT:simulationDuration

# Categorize buffers (land vs outlet)
buffer_names = myLFES.engSysNetPlaces
num_buffers = myLFES.numBufferOperandPairs

land_idxs = findall(name -> occursin("land", lowercase(name)), buffer_names)
outlet_idxs = findall(name -> occursin("outlet", lowercase(name)), buffer_names)

# Remove estuary from both if it's present
land_idxs = setdiff(land_idxs, [estuary_idx])
outlet_idxs = setdiff(outlet_idxs, [estuary_idx])

# Plot
default(fontfamily="sans", legendfontsize=10, guidefontsize=12, tickfontsize=10)
p = plot(title="Buffer Volumes Over Time (Excluding Estuary)",
         xlabel="Time Step", ylabel="Buffer Volume",
         legend=:topright, size=(900, 500))

# Plot outlet points in another color
for idx in outlet_idxs
    plot!(p, timesteps, QB_matrix[idx, :], color=:green, label=false)
end
plot!(p, [], [], color=:green, label="Outlet Points")

# Plot land segments in one color
for idx in land_idxs
    plot!(p, timesteps, QB_matrix[idx, :], color=:blue, label=false)
end
plot!(p, [], [], color=:blue, label="Land Segments")

display(p)

