# File name: wlsehfgse_watershed.jl
# Megan Harris

# Optimization Program

using JuMP, Gurobi, Statistics, DataFrames

print("Beginning build of optimization model...")
model  = Model(Gurobi.Optimizer)

# Simulation parameters
simulationDuration = Int(1)
deltaT = Int(1)
numTimeSteps = Int(simulationDuration / deltaT)
println("Time steps: $numTimeSteps (deltaT = $deltaT)")

# Simple county & segment identification
SECT = ["Agriculture","Developed"]

# Use existing CountyKey coverage
applied_keys = String.(collect(skipmissing(applied_df.CountyKey)))
loads_keys   = String.(collect(skipmissing(loads_df.CountyKey)))
counties     = sort!(collect(union(Set(applied_keys), Set(loads_keys))))
println("Found $(length(counties)) counties with coverage")

### Variables ###
@variable(model, QB[1:size(myLFES.engSysNet.Mpos,1), 1:numTimeSteps+1] >= 0)
@variable(model, U[1:myLFES.systemConcept.DOFS, 1:numTimeSteps] >= 0)
@variable(model, EU[1:myLFES.systemConcept.DOFS, 1:numTimeSteps])

# Starting counter for constraints written
numConstraintsAfterVariableDefinition = JuMP.num_constraints(model, count_variable_in_set_constraints=true)

### State Transition Function ###
println("Adding mass balance constraints over time...")
for k in 1:numTimeSteps
    @constraint(model,
        QB[:, k+1] .== QB[:, k] +
        (myLFES.engSysNet.Mpos-myLFES.engSysNet.Mneg)* U[:, k] * deltaT)
end
# Count constraints
numConstraintsAfterStateTransition = JuMP.num_constraints(model, count_variable_in_set_constraints=true)
numStateTransitionConstraints = numConstraintsAfterStateTransition - numConstraintsAfterVariableDefinition

### Initial Conditions ###
println("Setting initial conditions...")
@constraint(model, QB[:,1] .== 0)
# Count constraints
numConstraintsAfterInitCond = JuMP.num_constraints(model, count_variable_in_set_constraints=true)
numInitCondConstraints = numConstraintsAfterInitCond - numConstraintsAfterStateTransition

### Exogenous Constraints ###
println("Writing exogenous constraints...")
# Create county×sector totals (exogenous 'applied')
N_app_cs = Dict{Tuple{String,String}, Float64}()
P_app_cs = Dict{Tuple{String,String}, Float64}()

if !hasproperty(applied_df, :TotalNApplication); error("TotalNApplication column not found!"); end
if !hasproperty(applied_df, :TotalPApplication); error("TotalPApplication column not found!"); end

for row in eachrow(applied_df)
    county = String(row.CountyKey)
    sector = String(row.Sector)
    n_app = ismissing(row.TotalNApplication) || row.TotalNApplication === nothing ? 0.0 : Float64(row.TotalNApplication)
    p_app = ismissing(row.TotalPApplication)  || row.TotalPApplication  === nothing ? 0.0 : Float64(row.TotalPApplication)
    key = (county, sector)
    N_app_cs[key] = get(N_app_cs, key, 0.0) + n_app
    P_app_cs[key] = get(P_app_cs, key, 0.0) + p_app
end

println("Built 'applied' totals: N_app_cs=$(length(N_app_cs)), P_app_cs=$(length(P_app_cs))")

# Build accept-capability index maps
#   process 1 = accept Ag N
#   process 2 = accept Ag P
#   process 3 = accept Dev N
#   process 4 = accept Dev P

PROC_FOR = Dict(
    ("Agriculture", :N) => 1,
    ("Agriculture", :P) => 2,
    ("Developed",   :N) => 3,
    ("Developed",   :P) => 4,
)

# Mapping capability -> (resource -> transformResource -> segment, county) from process_CAST_data.jl
# (A) Accept caps grouped by (county, sector, nutrient)
ACCEPT_BY_CSN = Dict{Tuple{String,String,Symbol}, Vector{Int}}()
for j in accept_caps
    p  = myLFES.systemConcept.idxProcess[j]   # 1..4
    r  = myLFES.systemConcept.idxResource[j]
    haskey(resourceID_to_transformResource, r) || continue
    tr = resourceID_to_transformResource[r]

    cnty = transformResource_county(tr)   # now "#####"
    key = p == 1 ? (cnty, "Agriculture", :N) :
          p == 2 ? (cnty, "Agriculture", :P) :
          p == 3 ? (cnty, "Developed",   :N) :
          p == 4 ? (cnty, "Developed",   :P) : nothing
    key === nothing && continue
    push!(get!(ACCEPT_BY_CSN, key, Int[]), j)
end

# (B) Accept caps grouped by (segment, nutrient) — used for land->river transport
ACCEPT_BY_SEG_NUTRIENT = Dict{Tuple{String,Symbol}, Vector{Int}}()
for j in accept_caps
    r = myLFES.systemConcept.idxResource[j]
    haskey(resourceID_to_transformResource, r) || continue
    tr = resourceID_to_transformResource[r]
    seg = transformResource_riverSegment(tr)
    nu  = cap_nutrient(j)  # :N or :P
    push!(get!(ACCEPT_BY_SEG_NUTRIENT, (seg, nu), Int[]), j)
end

# Functions to sum flows and errors over a set of capabilities at time k
sumU(idx::Vector{Int}, k::Int)  = isempty(idx) ? zero(AffExpr) : sum(U[j, k]  for j in idx)
sumEU(idx::Vector{Int}, k::Int) = isempty(idx) ? zero(AffExpr) : sum(EU[j, k] for j in idx)

for c in counties, s in SECT
    rhsN = get(N_app_cs, (c, s), 0.0)
    rhsP = get(P_app_cs, (c, s), 0.0)
    capsN = get(ACCEPT_BY_CSN, (c, s, :N), Int[])
    capsP = get(ACCEPT_BY_CSN, (c, s, :P), Int[])
    for k in 1:numTimeSteps
        @constraint(model, sumU(capsN, k) - rhsN == sumEU(capsN, k))
        @constraint(model, sumU(capsP, k) - rhsP == sumEU(capsP, k))
    end
end

# Count constraints
numConstraintsAfterApplied = JuMP.num_constraints(model, count_variable_in_set_constraints=true)
numAppliedConstraints = numConstraintsAfterApplied - numConstraintsAfterInitCond
numAppliedConstraintsPerNutrientSector = Int.(numAppliedConstraints/4)

# Transport constraints
# --- Precompute per-transport-cap origin row in incMatPlus ---
# This code assumes two operands: nitrogen then phosphorus.
if myLFES.operand.number != 2
    error("This code assumes exactly two operands (N, P). Got myLFES.operand.number = $myLFES.operand.number")
end

# Map capability -> transport process index (you already have cap_to_transportProcess)
tp_for_cap = [ get(cap_to_transportProcess, j, 0) for j in transport_caps ]
@assert all(>(0), tp_for_cap) "Some transport caps lack a transport process row."

# Origin buffer index for each transport cap
orig_buf = [ myLFES.transportProcess.idxOrigin[tp] for tp in tp_for_cap ]

# Operand offset from refinement of the *transport process*
# nitrogen -> 0, phosphorus -> myLFES.buffer.number (rows are concatenated)
op_offset = [
    lowercase(String(myLFES.transportProcess.ref[tp])) == "phosphorus" ? myLFES.buffer.number : 0
    for tp in tp_for_cap
]

# Row in incMatPlus for each transport cap’s origin buffer–operand
# N rows: 1:myLFES.buffer.number, P rows: myLFES.buffer.number+1:2*myLFES.buffer.number
orig_row = orig_buf .+ op_offset

# Build inflow expressions at k=1:
# inflow[i] = dot(incMatPlus[origin_row[i], :], U[:,1])
inflow_expr = [
    sum(myLFES.engSysNet.Mpos[orig_row[i], k] * U[k, 1] for k in 1:myLFES.systemConcept.DOFS)
    for i in eachindex(transport_caps)
]

# capDF_tr is "one DF per capability" vector (missing for accepts)
capDF_tr = [ capDF[j] for j in transport_caps ]

# New WLSEHFGSE-style residual per capability:
# U_j[1] - DF_j * inflow_j[1] = EU_j[1]
@constraint(model,
    [i in eachindex(transport_caps)],
    U[transport_caps[i], 1] - capDF_tr[i] * inflow_expr[i] == EU[transport_caps[i], 1]
)

# Count constraints
numConstraintsAfterTransport = JuMP.num_constraints(model, count_variable_in_set_constraints=true)
numTransportConstraints = numConstraintsAfterTransport - numConstraintsAfterApplied

# EOS constraints
function land2stream_caps_in_county(cnty::String, nutrient::Symbol)
    [ j for j in transport_caps if haskey(cap_to_transportProcess, j) &&
        is_land_origin(cap_to_transportProcess[j]) &&
        begin
            _, _, cnt = origin_info(cap_to_transportProcess[j])
            (!ismissing(cnt)) && (String(cnt) == String(cnty)) && (cap_nutrient(j) == nutrient)
        end
    ]
end

for c in counties
    capsN = land2stream_caps_in_county(c, :N)
    if !isempty(capsN) && haskey(EOS_N, c)
        for k in 1:numTimeSteps
            @constraint(model, sumU(capsN, k) - EOS_N[c] == sumEU(capsN, k))
        end
    end

    capsP = land2stream_caps_in_county(c, :P)
    if !isempty(capsP) && haskey(EOS_P, c)
        for k in 1:numTimeSteps
            @constraint(model, sumU(capsP, k) - EOS_P[c] == sumEU(capsP, k))
        end
    end
end

# Count Constraints
numConstraintsAfterEOS = JuMP.num_constraints(model, count_variable_in_set_constraints=true)
numEOSConstraints = numConstraintsAfterEOS - numConstraintsAfterTransport

# Collect transport capabilities whose destination is the estuary, split by nutrient
caps_est_N = Int[]
caps_est_P = Int[]
for j in transport_caps
    haskey(cap_to_transportProcess, j) || continue
    tp = cap_to_transportProcess[j]
    is_estuary_destination(tp) || continue
    if cap_nutrient(j) == :N
        push!(caps_est_N, j)
    else
        push!(caps_est_P, j)
    end
end

println("EOT sources: N=$(length(caps_est_N)) caps, P=$(length(caps_est_P)) caps")

# Targets (from CAST)
sum_EOT_N = sum(v for (_,v) in EOT_N)
sum_EOT_P = sum(v for (_,v) in EOT_P)

# Tie the CAST bay totals to the modeled inflow INTO the estuary
for k in 1:numTimeSteps
    @constraint(model, sumU(caps_est_N, k) - sum_EOT_N == sumEU(caps_est_N, k))
    @constraint(model, sumU(caps_est_P, k) - sum_EOT_P == sumEU(caps_est_P, k))
end

# Count constraints
numConstraintsAfterEOT = JuMP.num_constraints(model, count_variable_in_set_constraints=true)
numEOTConstraints = numConstraintsAfterEOT - numConstraintsAfterEOS

# Between EOS and EOT (outlet to outlet) mass-balance check
# Collect outlet->outlet transport capabilities (exclude land origins & estuary destinations)
caps_oo_N = Int[]
caps_oo_P = Int[]
for j in transport_caps
    haskey(cap_to_transportProcess, j) || continue
    tp = cap_to_transportProcess[j]
    is_land_origin(tp)        && continue
    is_estuary_destination(tp) && continue
    if cap_nutrient(j) == :N
        push!(caps_oo_N, j)
    else
        push!(caps_oo_P, j)
    end
end
println("Outlet to Outlet caps: N=$(length(caps_oo_N)), P=$(length(caps_oo_P))")

# Totals from CAST
sum_EOS_N = sum(values(EOS_N))
sum_EOS_P = sum(values(EOS_P))
sum_EOT_N = sum(values(EOT_N))
sum_EOT_P = sum(values(EOT_P))

# Enforce:  sum of(outlet to outlet U)  =  sum of EOS − sum of EOT  (per nutrient)
for k in 1:numTimeSteps
    @constraint(model,
        sumU(caps_oo_N, k) - (sum_EOS_N - sum_EOT_N) == sumEU(caps_oo_N, k)
    )
    @constraint(model,
        sumU(caps_oo_P, k) - (sum_EOS_P - sum_EOT_P) == sumEU(caps_oo_P, k)
    )
end

# Count constraints
numConstraintsAfterST = JuMP.num_constraints(model, count_variable_in_set_constraints=true)
numStreamTideConstraints = numConstraintsAfterST - numConstraintsAfterEOT

### Building Objective Function

numCaps = myLFES.systemConcept.DOFS

# First, fill with ones to ensure capabilities without data (like some transport constraints)
    # Do not return 1/NaN^2
CU = fill(1.0, numCaps)

# F_E diagonal: one weight per capability
# With CU[j] = 1.0, this gives w_E[j] = 1 / max(1^2, 2) = 0.5 for all j
w_E = [1.0 / max(CU[j]^2, 2.0) for j in 1:numCaps]

alpha = 1e-10
beta  = 1e-12

@objective(model, Min,
    # E_Uᵀ F_E E_U  = Σ_j Σ_k w_E[j] * EU[j,k]^2
    sum(w_E[j] * sum(EU[j, k]^2 for k in 1:numTimeSteps) for j in 1:numCaps) +
    # Uᵀ A_U U with A_U = α I
    alpha * sum(U[j, k]^2 for j in 1:numCaps, k in 1:numTimeSteps) +
    # Q_Bᵀ A_QB Q_B with A_QB = β I (final time step = numTimeSteps + 1)
    beta * sum(QB[i, numTimeSteps + 1]^2 for i in 1:size(myLFES.engSysNet.Mpos,1))
)

optimize!(model)

println("Status: ", termination_status(model))
if termination_status(model) == MOI.OPTIMAL
    U_opt  = value.(U)
    QB_opt = value.(QB)

    println("Solution found!")

    # Create cap_results structure for mapping/plots
    cap_results = (U = U_opt, QB = QB_opt)

else
    println("Optimization failed: ", termination_status(model))
    cap_results = (U = zeros(myLFES.systemConcept.DOFS),
                   QB = zeros(size(myLFES.engSysNet.Mpos,1), 2))
end

println("Status: ", termination_status(model))
if termination_status(model) == MOI.OPTIMAL
    U_opt  = value.(U)
    QB_opt = value.(QB)
    EU_opt = value.(EU)

    println("Solution found!")

    # Create cap_results structure for mapping/plots
    cap_results = (U = U_opt, QB = QB_opt, EU = EU_opt)

    ##############################
    # ==== ERROR DIAGNOSTICS ====
    ##############################

    using Statistics, DataFrames

    numCaps = myLFES.systemConcept.DOFS

    # Helper: stats over a vector
    _stats(v) = isempty(v) ? (rmse=0.0, max=0.0, med=0.0, meanabs=0.0) :
        (rmse    = sqrt(mean(v.^2)),
         max     = maximum(abs.(v)),
         med     = median(abs.(v)),
         meanabs = mean(abs.(v)))

    ###############################
    # 1. Per-capability residuals
    ###############################

    # Single time-step, so just k = 1
    cap_residuals = [EU_opt[j, 1] for j in 1:numCaps]
    st_cap = _stats(cap_residuals)

    println("\n==== PER-CAPABILITY RESIDUALS (EU) ====")
    println("RMSE(EU)           = ", round(st_cap.rmse;   digits=4))
    println("Max |EU|           = ", round(st_cap.max;    digits=4))
    println("Median |EU|        = ", round(st_cap.med;    digits=4))
    println("Mean |EU|          = ", round(st_cap.meanabs;digits=4))

    # Optional: show top-k capabilities by |EU|
    top_k = 10
    abs_res = [(j, abs(cap_residuals[j])) for j in 1:numCaps]
    sort!(abs_res, by = x -> x[2], rev = true)
    println("\nTop $(min(top_k, length(abs_res))) capabilities by |EU|:")
    for (j, val) in abs_res[1:min(top_k, length(abs_res))]
        println("  cap ", j, ": |EU| = ", round(val; digits=4))
    end

    #######################################
    # 2. Data-space diagnostics: Applied
    #######################################

    # helper sums for optimized values
    sumU_opt(idx::Vector{Int}, k::Int) =
        isempty(idx) ? 0.0 : sum(U_opt[j, k] for j in idx)

    println("\n==== APPLIED (N,P) BY COUNTY & SECTOR ====")

    applied_rows = DataFrame(
        County = String[],
        Sector = String[],
        yN = Float64[], yhatN = Float64[],
        yP = Float64[], yhatP = Float64[]
    )

    for c in counties, s in SECT
        rhsN  = get(N_app_cs, (c, s), 0.0)
        rhsP  = get(P_app_cs, (c, s), 0.0)
        capsN = get(ACCEPT_BY_CSN, (c, s, :N), Int[])
        capsP = get(ACCEPT_BY_CSN, (c, s, :P), Int[])

        modelN = sumU_opt(capsN, 1)
        modelP = sumU_opt(capsP, 1)

        push!(applied_rows, (String(c), String(s), rhsN, modelN, rhsP, modelP))
    end

    # R² / RMSE helper
    function r2_nrmse(y::AbstractVector{<:Real}, yhat::AbstractVector{<:Real})
        length(y) == length(yhat) || return (R2=NaN, RMSE=NaN, NRMSE_mean=NaN)
        y     = Float64.(y)
        yhat  = Float64.(yhat)
        resid = yhat .- y
        sse   = sum(resid.^2)
        sst   = sum((y .- mean(y)).^2)
        rmse  = sqrt(mean(resid.^2))
        nrmse_mean = (mean(abs.(y)) > 0) ? rmse / mean(abs.(y)) : NaN
        R2 = (sst > 0) ? 1 - sse/sst : NaN
        return (R2=R2, RMSE=rmse, NRMSE_mean=nrmse_mean)
    end

    ap_yN    = applied_rows.yN
    ap_yhatN = applied_rows.yhatN
    ap_yP    = applied_rows.yP
    ap_yhatP = applied_rows.yhatP

    fit_ap_N = r2_nrmse(ap_yN, ap_yhatN)
    fit_ap_P = r2_nrmse(ap_yP, ap_yhatP)

    pct(x) = round(100*x; digits=2)

    println("\n==== APPLIED TOTALS: GOODNESS OF FIT ====")
    println("N:  R² = ", round(fit_ap_N.R2;  digits=4),
            ", RMSE = ", round(fit_ap_N.RMSE; digits=3),
            ", NRMSE(mean) = ", pct(fit_ap_N.NRMSE_mean), "%")
    println("P:  R² = ", round(fit_ap_P.R2;  digits=4),
            ", RMSE = ", round(fit_ap_P.RMSE; digits=3),
            ", NRMSE(mean) = ", pct(fit_ap_P.NRMSE_mean), "%")

    #######################################
    # 3. EOS (land->stream) by county
    #######################################

    println("\n==== EOS (LAND->STREAM) COUNTY TOTALS ====")

    eos_rows = DataFrame(
        County = String[],
        yN = Float64[], yhatN = Float64[],
        yP = Float64[], yhatP = Float64[]
    )

    for c in counties
        hasN = haskey(EOS_N, c)
        hasP = haskey(EOS_P, c)
        (!hasN && !hasP) && continue

        capsN = land2stream_caps_in_county(c, :N)
        capsP = land2stream_caps_in_county(c, :P)

        yN     = hasN ? EOS_N[c] : NaN
        yhatN  = hasN ? sumU_opt(capsN, 1) : NaN
        yP     = hasP ? EOS_P[c] : NaN
        yhatP  = hasP ? sumU_opt(capsP, 1) : NaN

        push!(eos_rows, (String(c), yN, yhatN, yP, yhatP))
    end

    yN_eos    = filter(!isnan, eos_rows.yN)
    yhatN_eos = filter(!isnan, eos_rows.yhatN)
    yP_eos    = filter(!isnan, eos_rows.yP)
    yhatP_eos = filter(!isnan, eos_rows.yhatP)

    fit_eos_N = r2_nrmse(yN_eos, yhatN_eos)
    fit_eos_P = r2_nrmse(yP_eos, yhatP_eos)

    println("\nEOS (county totals):")
    println("  N:  R² = ", round(fit_eos_N.R2;  digits=4),
            ", RMSE = ", round(fit_eos_N.RMSE; digits=3),
            ", NRMSE(mean) = ", pct(fit_eos_N.NRMSE_mean), "%")
    println("  P:  R² = ", round(fit_eos_P.R2;  digits=4),
            ", RMSE = ", round(fit_eos_P.RMSE; digits=3),
            ", NRMSE(mean) = ", pct(fit_eos_P.NRMSE_mean), "%")

    #######################################
    # 4. EOT (estuary) totals
    #######################################

    eotN_target = sum(v for (_, v) in EOT_N)
    eotP_target = sum(v for (_, v) in EOT_P)

    eotN_model = sum(U_opt[j,1] for j in caps_est_N)
    eotP_model = sum(U_opt[j,1] for j in caps_est_P)

    eotN_resid = eotN_model - eotN_target
    eotP_resid = eotP_model - eotP_target

    eotN_pcterr = abs(eotN_target) > 0 ? 100*abs(eotN_resid)/abs(eotN_target) : NaN
    eotP_pcterr = abs(eotP_target) > 0 ? 100*abs(eotP_resid)/abs(eotP_target) : NaN

    println("\n==== EOT (ESTUARY TOTALS) ====")
    println("N: target = ", round(eotN_target; digits=3),
            ", model = ", round(eotN_model; digits=3),
            ", abs err = ", round(abs(eotN_resid); digits=3),
            " (", round(eotN_pcterr; digits=2), "% )")
    println("P: target = ", round(eotP_target; digits=3),
            ", model = ", round(eotP_model; digits=3),
            ", abs err = ", round(abs(eotP_resid); digits=3),
            " (", round(eotP_pcterr; digits=2), "% )")

    #######################################
    # 5. Outlet->Outlet (stream->tide) diagnostics
    #######################################

    stN_target = sum(values(EOS_N)) - sum(values(EOT_N))
    stP_target = sum(values(EOS_P)) - sum(values(EOT_P))

    stN_model = sum(U_opt[j,1] for j in caps_oo_N)
    stP_model = sum(U_opt[j,1] for j in caps_oo_P)

    stN_resid = stN_model - stN_target
    stP_resid = stP_model - stP_target

    stN_pcterr = abs(stN_target) > 0 ? 100*abs(stN_resid)/abs(stN_target) : NaN
    stP_pcterr = abs(stP_target) > 0 ? 100*abs(stP_resid)/abs(stP_target) : NaN

    println("\n==== STREAM->TIDE (OUTLET->OUTLET AGGREGATE) ====")
    println("N: target = ", round(stN_target; digits=3),
            ", model = ", round(stN_model; digits=3),
            ", abs err = ", round(abs(stN_resid); digits=3),
            " (", round(stN_pcterr; digits=2), "% )")
    println("P: target = ", round(stP_target; digits=3),
            ", model = ", round(stP_model; digits=3),
            ", abs err = ", round(abs(stP_resid); digits=3),
            " (", round(stP_pcterr; digits=2), "% )")

    #######################################
    # 6. WLSE objective contribution from EU
    #######################################

    # assumes w_E and numTimeSteps are in scope
    Z_EU = sum(w_E[j] * sum(EU_opt[j,k]^2 for k in 1:numTimeSteps) for j in 1:numCaps)
    println("\nWLSE error term (EUᵀ F_E EU): Z_EU = ", round(Z_EU; digits=4))

    println("\n==== TRANSPORT CAPABILITY RESIDUALS (EU, TRANSPORT CAPS ONLY) ====")

    # transport_caps is your existing vector of capability indices
    E_trans_caps = [EU_opt[j, 1] for j in transport_caps]

    _stats(v) = isempty(v) ? (rmse=0.0, max=0.0, med=0.0, meanabs=0.0) :
        (rmse    = sqrt(mean(v.^2)),
        max     = maximum(abs.(v)),
        med     = median(abs.(v)),
        meanabs = mean(abs.(v)))

    st_trans = _stats(E_trans_caps)

    println("RMSE(EU)           = ", round(st_trans.rmse;   digits=4))
    println("Max |EU|           = ", round(st_trans.max;    digits=4))
    println("Median |EU|        = ", round(st_trans.med;    digits=4))
    println("Mean |EU|          = ", round(st_trans.meanabs;digits=4))

    # Top 10 transport caps by |EU|
    top_k_tr = 10
    pairs_tr = [(transport_caps[i], abs(E_trans_caps[i])) for i in eachindex(transport_caps)]
    sort!(pairs_tr, by = x -> x[2], rev = true)

    println("\nTop $(min(top_k_tr,length(pairs_tr))) TRANSPORT capabilities by |EU|:")
    for (j, val) in pairs_tr[1:min(top_k_tr, length(pairs_tr))]
        println("  cap ", j, ": |EU| = ", round(val; digits=4))
    end

    println("\n==== RELATIVE TRANSPORT ERRORS |EU| / |U| (TRANSPORT CAPS) ====")

    eps_u = 1e-6

    rel_trans = [
        abs(EU_opt[j,1]) / max(abs(U_opt[j,1]), eps_u)
        for j in transport_caps
    ]

    st_rel_tr = _stats(rel_trans)

    println("RMSE(|EU|/|U|)      = ", round(st_rel_tr.rmse;   digits=4))
    println("Max |EU|/|U|        = ", round(st_rel_tr.max;    digits=4))
    println("Median |EU|/|U|     = ", round(st_rel_tr.med;    digits=4))
    println("Mean |EU|/|U|       = ", round(st_rel_tr.meanabs;digits=4))

    top_k_rel_tr = 10
    rel_pairs_tr = [(transport_caps[i], rel_trans[i]) for i in eachindex(transport_caps)]
    sort!(rel_pairs_tr, by = x -> x[2], rev = true)

    println("\nTop $(min(top_k_rel_tr,length(rel_pairs_tr))) transport caps by relative error:")
    for (j, val) in rel_pairs_tr[1:min(top_k_rel_tr, length(rel_pairs_tr))]
        println("  cap ", j, ": |EU|/|U| = ", round(val; digits=4),
                ", U = ", round(U_opt[j,1]; digits=2),
                ", EU = ", round(EU_opt[j,1]; digits=2))
    end

else
    println("Optimization failed: ", termination_status(model))
    cap_results = (U = zeros(myLFES.systemConcept.DOFS),
                   QB = zeros(size(myLFES.engSysNet.Mpos,1), 2),
                   EU = zeros(myLFES.systemConcept.DOFS, numTimeSteps))
end

println("Number of State Transition Constraints: $numStateTransitionConstraints")
println("Number of Initial Condition Constraints: $numInitCondConstraints")
println("Number of Accept Nutrient Constraints: $numAppliedConstraints")
println("Number of Accept Nutrient Constraints Per Nutrient Per Sector: $numAppliedConstraintsPerNutrientSector")
println("Number of Transport Constraints: $numTransportConstraints")
println("Number of EOS Constraints: $numEOSConstraints")
println("Number of EOT Constraints: $numEOTConstraints")
println("Number of stream to tide constraints: $numStreamTideConstraints")
