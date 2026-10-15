# File name: decompose_holdout.jl
# Megan Harris (2026-10 revision)
#
# Decomposes the hold-out difference between the estimated delivery to the Bay and CAST's EOT
# into sequential steps. Run AFTER run_wlsehfgse_watershed.jl with USE_EOT = false (it uses the
# network, measurements and solution that are still in memory):
#
#   USE_EOT = false
#   include("1-Code/3-Simulation/wlsehfgse/run_wlsehfgse_watershed.jl")
#   include("1-Code/3-Simulation/wlsehfgse/decompose_holdout.jl")
#
# Each step is a forward calculation on the network (no optimization):
#   D0  route CAST's EOR loads through the network with CAST's delivery factors
#   D1  same, with factors > 1 capped at 1 (what a mass-conserving network can pass)
#   D2  route the ESTIMATED land->outlet flows with the capped factors
#   Dest  estimated delivery to the Bay (the estimator solution)
# Steps (percentage points of CAST EOT, they sum to the total):
#   D0 - EOT     routing check: does the network reproduce CAST's delivery?
#   D1 - D0      effect of factors > 1
#   D2 - D1      effect of the estimated land->outlet flows differing from the EOR loads
#   Dest - D2    effect of the estimated in-river flows differing from factor x inflow

using SparseArrays, Printf

@assert @isdefined(cap_results) "Run the estimator first (cap_results not found)."
USE_EOT && @warn "USE_EOT = true: EOT was fitted, so this is not a hold-out decomposition."

Mpos   = myLFES.engSysNet.Mpos
nCaps  = size(Mpos, 2)
U_opt  = vec(cap_results.U[:, 1])
Mrows  = Mpos[orig_row, :]                       # row i: injections into the origin buffer of transport cap i
DF     = Float64.(coalesce.(capDF_tr, 1.0))
is_N   = [cap_is_N(j) for j in transport_caps]
est_N  = Set(caps_est_N); est_P = Set(caps_est_P)

# Forward routing: land caps carry `land_flow`; every other transport cap carries DF * inflow.
function route(land_flow::Vector{Float64}, df::Vector{Float64}; maxiter = 2000, tol = 1e-6)
    u = zeros(nCaps)
    for i in eachindex(transport_caps)
        is_land_tr[i] && (u[transport_caps[i]] = land_flow[i])
    end
    for it in 1:maxiter
        inflow = Mrows * u
        delta  = 0.0
        for i in eachindex(transport_caps)
            is_land_tr[i] && continue
            j   = transport_caps[i]
            new = df[i] * inflow[i]
            delta = max(delta, abs(new - u[j]))
            u[j] = new
        end
        delta < tol && return u
    end
    @warn "routing did not converge"
    return u
end

delivered(u, est) = sum(u[j] for j in est)

eor_land = [is_land_tr[i] ? eor_target[i] : 0.0 for i in eachindex(transport_caps)]
est_land = [is_land_tr[i] ? U_opt[transport_caps[i]] : 0.0 for i in eachindex(transport_caps)]
DFcap    = min.(DF, 1.0)

u0 = route(eor_land, DF)
u1 = route(eor_land, DFcap)
u2 = route(est_land, DFcap)

println("\n==== HOLD-OUT DECOMPOSITION (percentage points of CAST EOT) ====")
for (lbl, est, EOT) in (("N", est_N, sum_EOT_N), ("P", est_P, sum_EOT_P))
    D0 = delivered(u0, est); D1 = delivered(u1, est); D2 = delivered(u2, est)
    De = delivered(U_opt, est)
    pp(x) = @sprintf("%+.2f", 100 * x / EOT)
    println("\n", lbl, ":  CAST EOT = ", @sprintf("%.4g", EOT), "   estimated = ", @sprintf("%.4g", De),
            "   total = ", pp(De - EOT))
    println("  routing check (CAST EOR, CAST factors)       D0 - EOT  = ", pp(D0 - EOT))
    println("  factors > 1 capped at 1                       D1 - D0   = ", pp(D1 - D0))
    println("  estimated land->outlet flows vs EOR           D2 - D1   = ", pp(D2 - D1))
    println("  estimated in-river flows vs factor x inflow   Dest - D2 = ", pp(De - D2))
end

# Land segments whose EOR target exceeds what the estimator puts on the segment
println("\n==== LAND SEGMENTS RECEIVING LESS THAN THEIR EOR TARGET ====")
inflow_opt = Mrows * U_opt
for (lbl, want) in (("N", true), ("P", false))
    idx = [i for i in eachindex(transport_caps) if is_land_tr[i] && is_N[i] == want]
    short = [max(eor_target[i] - inflow_opt[i], 0.0) for i in idx]
    n = count(>(1.0), short)
    println(lbl, ": ", n, " of ", length(idx), " land segments; total shortfall = ",
            @sprintf("%.4g", sum(short)), " lb  (EOR total ", @sprintf("%.4g", sum(eor_target[i] for i in idx)), ")")
end
