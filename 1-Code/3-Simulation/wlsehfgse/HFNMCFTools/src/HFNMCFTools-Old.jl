# Copyright (c) 2022-2025 Engineering Systems Analytics LLC
# @author: Amro M. Farid
# @version: 4.6.0
# @Modified: 12/24/2025

module HFNMCFTools

using PrettyPrint
using JSON3, JuMP
using CPLEX, Gurobi, HiGHS
using SparseArrays, CSV, DataFrames
using PrecompileTools: @setup_workload, @compile_workload         # This is a small dependency

############ Function Library #################
mutable struct MutableStruct
    fields::Dict{Symbol,Any}
    MutableStruct() = new(Dict{Symbol,Any}())
end
function Base.getproperty(m::MutableStruct, f::Symbol)
    if f === :fields
        return getfield(m, :fields)
    elseif haskey(m.fields, f)
        return m.fields[f]
    else
        return getfield(m, f)
    end
end
function Base.setproperty!(m::MutableStruct, f::Symbol, v)
    if f === :fields
        setfield!(m, :fields, v)
    else
        m.fields[f] = v
    end
end
function parseJSON3(x)
    x = deepcopy(x)
    if x isa JSON3.Object
        obj = MutableStruct()
        for (k,v) in pairs(x)
            setproperty!(obj, Symbol(k), parseJSON3(v))
        end
        return obj
    elseif x isa JSON3.Array
        return [parseJSON3(v) for v in x]
    else
        return x
    end
end
function createJSON3(x)
    if x isa MutableStruct
        return Dict(String(k) => createJSON3(v) for (k, v) in x.fields)
    elseif x isa AbstractVector
        return [createJSON3(v) for v in x]
    else
        # numbers, strings, bools, nothing
        return x
    end
end
function setVariableDomain!(x,varDomain,varName)
    idxLBinary  = occursin.("binary",  varDomain)
    idxLInteger = occursin.("integer", varDomain)
    idxLReal    = occursin.("real", varDomain)
    idxLPos     = occursin.("+", varDomain)
    temp = idxLBinary .| idxLInteger .| idxLReal
    try
        if !all(temp)
            temp = findall(.!temp)
            throw(ArgumentError("Fail! Decision variable must be binary, integer, or real! Inspect indices: $temp in $varName"))
        end
    catch e
        println("$e.  Abort! Abort!")
        return false
    end
    if ndims(x) == 1
        set_binary.(x[idxLBinary])
        set_integer.(x[idxLInteger])
        set_lower_bound.(x[idxLPos], 0)
    elseif ndims(x) == 2
        set_binary.(x[idxLBinary, :])
        set_integer.(x[idxLInteger, :])
        set_lower_bound.(x[idxLPos,:], 0)
    end
    return true
end
function mutableStruct2SparseMat(sparseMatDict)
    if isa(sparseMatDict, MutableStruct)
        tempData    = convert.(Float64,sparseMatDict.data)
        tempCoords1 = convert.(Int64,sparseMatDict.coords[1]) .+ 1
        tempCoords2 = convert.(Int64,sparseMatDict.coords[2]) .+ 1
        tempShape   = convert.(Int64,sparseMatDict.myShape)
        A = sparse(tempCoords1, tempCoords2, tempData, tempShape[1], tempShape[2])
    else
        A = sparseMatDict
    end
    return A
end
function sparseMat2MutableStruct(A)
    if isa(A,SparseMatrixCSC)
        ms = MutableStruct()
        idxRows, idxCols, vals = findnz(A)
        # convert to 0-based indexing to match your format
        ms.coords = [idxRows .- 1, idxCols .- 1]
        ms.data    = vals
        ms.myShape = [size(A, 1), size(A, 2)]
        ms.myClass = "coo_array"
    else
        ms = A
    end
    return ms
end
function convertVecOfVec2Matrix(myMatrix)
    A = vcat(myMatrix'...)
    return A
end
# convertVecOfVec2Matrix(myMatrix::Vector{<:AbstractVector}) = reduce(vcat, myMatrix)
function convertMatrix2VecOfVec(A)
    return [collect(row) for row in eachrow(A)]
end
convertMatrix2VecOfVec(A::AbstractMatrix) = [collect(row) for row in eachrow(A)]

function cleanZeros(mat::AbstractArray)
    return map(x -> isZero(x) ? 0.0 : x, mat)
end

isEmpty(::Nothing) = true
isEmpty(x) = isempty(x)

isZero(::Nothing) = true
isZero(x) = iszero(x)

function loadHFNMCFData(inputFilePath)
    print("\033c")
    println("Loading Optimization Model Data")
    # Reformatting variables
    myLFES = parseJSON3(JSON3.read(inputFilePath))
    myLFES.engSysNet.Mneg = mutableStruct2SparseMat(myLFES.engSysNet.Mneg)
    myLFES.engSysNet.Mpos = mutableStruct2SparseMat(myLFES.engSysNet.Mpos)
    myLFES.operand.Mneg = [mutableStruct2SparseMat(myLFES.operand.Mneg[l]) for l in 1:myLFES.operand.number]
    myLFES.operand.Mpos = [mutableStruct2SparseMat(myLFES.operand.Mpos[l]) for l in 1:myLFES.operand.number]
    myLFES.operand.syncMat = [mutableStruct2SparseMat(myLFES.operand.syncMat[l]) for l in 1:myLFES.operand.number]
    if myLFES.hasProcessCost
        myLFES.engSysNet.pnTransitions.linearCostCoeff = convertVecOfVec2Matrix(myLFES.engSysNet.pnTransitions.linearCostCoeff)
    end
    for l in 1:myLFES.operand.number
        if myLFES.operand.hasTransitionCost[l]
            myLFES.operand.pnTransitions[l].linearCostCoeff = convertVecOfVec2Matrix(myLFES.operand.pnTransitions[l].linearCostCoeff)
        end
    end
    myLFES.operand.XS = Vector{Union{Nothing, MutableStruct}}(fill(nothing, myLFES.operand.number))
    myLFES.operand.XE = Vector{Union{Nothing, MutableStruct}}(fill(nothing, myLFES.operand.number))
    myLFES.operand.Uneg = Vector{Union{Nothing, MutableStruct}}(fill(nothing, myLFES.operand.number))
    myLFES.operand.Upos = Vector{Union{Nothing, MutableStruct}}(fill(nothing, myLFES.operand.number))
    return myLFES
end

function buildHFNMCFProblem(myLFES)
    println("Building Optimization Model")
    if lowercase(myLFES.optimizer) == "cplex"
        HFNMCF = Model(CPLEX.Optimizer)
    elseif lowercase(myLFES.optimizer) == "gurobi"
        HFNMCF = Model(Gurobi.Optimizer)
    else
        HFNMCF = Model(HiGHS.Optimizer)
    end
    # # Variable Declaration
    println("\t Declaring Decision Variables")
    if myLFES.hasESN_STF1
        # These are the amounts of operands stored in each place at any momment in time k in the engineering system net places
        @variable(HFNMCF, QB[1:myLFES.buffer.number * myLFES.operand.number, 1:myLFES.simHorizon])
        setVariableDomain!(QB,myLFES.engSysNet.pnPlaces.varDomain,"myLFES.engSysNet.pnPlaces")
    else
        QB = fill(nothing, 1,1)
    end
    if myLFES.hasESN_STF2
        # These are the amounts of operands stored in each place at any momment in time k in the engineering system net transitions
        @variable(HFNMCF, QE[1:myLFES.systemConcept.DOFS, 1:myLFES.simHorizon])
        setVariableDomain!(QE,myLFES.engSysNet.pnTransitions.varDomain,"myLFES.engSysNet.pnTransitions")
    else
        QE = fill(nothing,1,1)
    end
    if myLFES.hasESN_STF1 || myLFES.hasESN_STF2 
        # These are the number of times an engineering system net transition is initiated at a moment in time k. 
        @variable(HFNMCF, UEneg[1:myLFES.systemConcept.DOFS, 1:myLFES.simHorizon-1] >= 0)
        setVariableDomain!(UEneg,myLFES.engSysNet.pnTransitions.varDomain,"myLFES.engSysNet.pnTransitions")
        # These are the number of times an engineering system net transition is terminated at a moment in time k. 
        @variable(HFNMCF, UEpos[1:myLFES.systemConcept.DOFS, 1:myLFES.simHorizon-1] >= 0)
        setVariableDomain!(UEpos,myLFES.engSysNet.pnTransitions.varDomain,"myLFES.engSysNet.pnTransitions")
    else
        UEneg = fill(nothing,1,1)
        UEpos = fill(nothing,1,1)
    end
    # Pre-allocate arrays to hold JuMP variable matrices
    QSL   = Vector{Any}(nothing, myLFES.operand.number)   # Operand net places
    QEL   = Vector{Any}(nothing, myLFES.operand.number)   # Operand net transitions (amount stored)
    ULneg = Vector{Any}(nothing, myLFES.operand.number)   # Number of times a transition is initiated
    ULpos = Vector{Any}(nothing, myLFES.operand.number)   # Number of times a transition is terminated

    # Loop over operand nets
    for l in 1:myLFES.operand.number
        m, n = myLFES.operand.MFull[l].myShape
        operandNetSizes = [Tuple(myLFES.operand.MFull[l].myShape) for l in 1:myLFES.operand.number]
        if myLFES.operand.hasOperandNet_STF1[l]
            # These are the amounts of operands stored in each place at any momment in time k in the operand net places
            QSL[l] = @variable(HFNMCF, [1:m, 1:myLFES.simHorizon])  
            setVariableDomain!(QSL[l],myLFES.operand.pnPlaces[l].varDomain, "myLFES.operand.pnPlaces[$l]")
        end
        if myLFES.operand.hasOperandNet_STF2[l]
            # These are the amounts of operands stored in each place at any momment in time k in the operand net transitions
            QEL[l] = @variable(HFNMCF, [1:n, 1:myLFES.simHorizon])  
            setVariableDomain!(QEL[l],myLFES.operand.pnTransitions[l].varDomain, "myLFES.operand.pnTransitions[$l]")
        end
        if myLFES.operand.hasOperandNet_STF1[l] || myLFES.operand.hasOperandNet_STF2[l]
            # These are the number of times an operand net transition is initiated at a moment in time k. 
            ULneg[l] = @variable(HFNMCF, [1:n, 1:myLFES.simHorizon])  
            setVariableDomain!(ULneg[l],myLFES.operand.pnTransitions[l].varDomain,"myLFES.operand.pnTransitions[$l]")
            # These are the number of times an operand net transition is terminated at a moment in time k. 
            ULpos[l] = @variable(HFNMCF, [1:n, 1:myLFES.simHorizon])
            setVariableDomain!(ULpos[l],myLFES.operand.pnTransitions[l].varDomain,"myLFES.operand.pnTransitions[$l]")
        end
    end
    # # Engineering System Net & Operand Net State Transition Functions
    for k in 1:myLFES.simHorizon-1
        # Engineering System Net State Transition Function
        if myLFES.hasESN_STF1
            println("\t Building Engineering System Net State Transition Function Constraints - QB:  Time Step $k")
            # The engineering system net state transition function ONE is built up one time step at a time to avoid memory limitations. 
            if !myLFES.hasESN_Duration || all(isZero,myLFES.engSysNet.pnTransitions.duration)
                # This condition eliminates the need for the UEpos[:,k] variable
                @constraint(HFNMCF, QB[:,k+1] .== QB[:,k] + (myLFES.engSysNet.Mpos - myLFES.engSysNet.Mneg) * UEneg[:,k] * myLFES.deltaT, base_name = "ESN_STF1_$(k)")
            else
                # This is the default general case for the UEpos[:,k] variable
                @constraint(HFNMCF, QB[:,k+1] .== QB[:,k] + (myLFES.engSysNet.Mpos * UEpos[:,k] * myLFES.deltaT) - (myLFES.engSysNet.Mneg * UEneg[:,k] * myLFES.deltaT), base_name = "ESN_STF1_$(k)")
            end
        end
        if myLFES.hasESN_STF2
            println("\t Building Engineering System Net State Transition Function Constraints - QE:  Time Step $k")
            #  The engineering system net state transition function TWO is built up one time step at a time to avoid memory limitations. 
            if !myLFES.hasESN_Duration || all(isZero,myLFES.engSysNet.pnTransitions.duration)
                # This condition eliminates the need for the UEpos[:,k] variable 
                @constraint(HFNMCF, QE[:,k+1] .== QE[:,k] - (UEpos[:,k] + UEneg[:,k]) * myLFES.deltaT, base_name = "ESN_STF2_$(k)")
            else
                # This is the default general case for the UEpos[:,k] variable
                @constraint(HFNMCF, QE[:,k+1] .== QE[:,k] - (UEpos[:,k] * myLFES.deltaT) + (UEneg[:,k] * myLFES.deltaT), base_name = "ESN_STF2_$(k)")
            end
        end
        if myLFES.hasESN_Duration
            println("\t Building Engineering System Net State Transition Function Constraints - Duration:  Time Step $k")
            # The engineering system net state transition function duration constraint is built up one time step and one capability at a time by necessity.
            if !all(isZero,myLFES.engSysNet.pnTransitions.duration)
                # This is the default general case of the UEpos[:,k] variable 
                for psi in 1:myLFES.systemConcept.DOFS
                    if (k + myLFES.engSysNet.pnTransitions.duration[psi]) <= myLFES.simHorizon-1
                        @constraint(HFNMCF, UEpos[psi, (k+myLFES.engSysNet.pnTransitions.duration[psi])] .== UEneg[psi, k], base_name = "ESN_STFDuration_$(k)")
                    end
                end
            else
                # This is the special case of the UEpos[:,k] variable
            end
        end
        # The engineering system net state transition function has a ramping constraint on the transitions.  
        if myLFES.hasProcessRamp && k<=myLFES.simHorizon-2
            local idx
            idx = .!isEmpty.(myLFES.engSysNet.pnTransitions.upperBoundRamp)
            @constraint(HFNMCF, UEneg[idx,k+1] - UEneg[idx,k] .<= myLFES.engSysNet.pnTransitions.upperBoundRamp[idx], base_name = "ESN_UpperBoundRamp_$(k)")
            @constraint(HFNMCF, UEneg[idx,k+1] - UEneg[idx,k] .>= myLFES.engSysNet.pnTransitions.lowerBoundRamp[idx], base_name = "ESN_LowerBoundRamp_$(k)")
        end
        # Operand Net State Transition Function
        for l in 1: myLFES.operand.number
            if myLFES.operand.hasOperandNet_STF1[l]
                println("\t Building Operand Net Number $l State Transition Function Constraints - QSL:  Time Step $k")
                # The operand net state transition function ONE is built up one time step at a time to avoid memory limitations. 
                if all(isZero,myLFES.operand.pnTransitions[l].duration)
                    # This condition eliminates the need for the ULpos[:,k] variable
                    @constraint(HFNMCF, QSL[l][:,k+1] .== QSL[l][:,k] + (myLFES.operand.Mpos[l] - myLFES.operand.Mneg[l]) * ULneg[l][:,k] * myLFES.deltaT, base_name = "OperandNet$(l)_STF1_$(k)")
                else
                    # This is the default general case for the ULpos[:,k] variable
                    @constraint(HFNMCF, QSL[l][:,k+1] .== QSL[l][:,k] + (myLFES.operand.Mpos[l] * ULpos[l][:,k] * myLFES.deltaT) - (myLFES.operand.Mneg[l] * ULneg[l][:,k] * myLFES.deltaT), base_name = "OperandNet$(l)_STF1_$(k)")
                end
            end
            if myLFES.operand.hasOperandNet_STF2[l]
                println("\t Building Operand Net Number $l State Transition Function Constraints - QEL:  Time Step $k")
                # The operand net state transition function TWO is built up one time step at a time to avoid memory limitations. 
                if all(isZero,myLFES.operand.pnTransitions[l].duration)
                    # This condition eliminates the need for the ULpos[:,k] variable
                    @constraint(HFNMCF, QEL[l][:,k+1] .== QEL[l][:,k] - (ULpos[l][:,k] + ULneg[l][:,k]) * myLFES.deltaT, base_name = "OperandNet$(l)_STF2_$(k)")  
                else
                    # This is the default general case for the ULpos[:,k] variable
                    @constraint(HFNMCF, QEL[l][:,k+1] .== QEL[l][:,k] - (ULpos[l][:,k] * myLFES.deltaT) + (ULneg[l][:,k] * myLFES.deltaT), base_name = "OperandNet$(l)_STF2_$(k)")
                end
            end
            if myLFES.operand.hasOperandNet_Duration[l]
                println("\t Building Operand Net Number $l State Transition Function Constraints - Duration:  Time Step $k")
                # The operand net state transition function duration constraint is built up one time step and one capability at a time by necessity.
                if !all(isZero, myLFES.operand.pnTransitions[l].duration) 
                    # This is the default general case of the UEpos[:,k] variable
                    for x in 1:myLFES.operand.pnTransitions[l].number
                        if (k + myLFES.operand.pnTransitions[l].duration[x]) <= myLFES.simHorizon-1
                            @constraint(HFNMCF, ULpos[l][x, (k+myLFES.operand.pnTransitions[l].duration[x])] .== ULneg[l][x, k], base_name = "OperandNet$(l)_STFDuration_$(k)")
                        end
                        if k <= myLFES.operand.pnTransitions[l].duration[x]
                            @constraint(HFNMCF, ULpos[l][x,k] .== 0, base_name = "OperandNet$(l)_STFDuration_$(k)")
                        end
                    end
                else
                    # This is the special case of the ULpos[:,k] variable
                end
            end
            if myLFES.operand.hasSyncMatNeg[l]
                # AMRO STOPPED HERE.  must validate hasSyncMatNeg and Pos.  must convert the syncmats from dicts to sparse.  
                @constraint(HFNMCF,ULneg[l][:,k] - myLFES.operand.syncMat[l] * UEneg[:,k] .== 0, base_name = "OperandNet$(l)_SyncNeg_$(k)")
            end
            if myLFES.operand.hasSyncMatPos[l]
                @constraint(HFNMCF,ULpos[l][:,k] - myLFES.operand.syncMat[l] * UEpos[:,k] .== 0, base_name = "OperandNet$(l)_SyncPos_$(k)")
            end
        end
    end
    # # Exogenous Value Constraints on Engineering System Net Transitions
    if myLFES.hasProcessValues
        println("\t Building Engineering System Net Transition Exogenous Value Constraints")
        idx = .!isEmpty.(myLFES.engSysNet.pnTransitions.value)
        @constraint(HFNMCF, UEneg[idx, :] .== convertVecOfVec2Matrix(myLFES.engSysNet.pnTransitions.value[idx]), base_name = "ESN_UEValue")
    end
    # # Initial Condition Constraints on Engineering System Net Places
    if myLFES.hasBufferInitCond
        println("\t Building Engineering System Net Place Initial Conditions")
        @constraint(HFNMCF, QB[:, 1] .== myLFES.engSysNet.pnPlaces.initCond, base_name = "ESN_QBInitCond")
    end
    # # Initial Condition Constraints on Engineering System Net Transitions
    if myLFES.hasProcessInitCond && myLFES.hasESN_Duration
        println("\t Building Engineering System Net Transition Initial Conditions")
        @constraint(HFNMCF, QE[:, 1] .== myLFES.engSysNet.pnTransitions.initCond, base_name = "ESN_QEInitCond")
    end
    # # Final Condition Constraints on Engineering System Net Places
    if myLFES.hasBufferFinalCond
        println("\t Building Engineering System Net Transition Final Conditions")
        @constraint(HFNMCF, QB[:, myLFES.simHorizon] .== myLFES.engSysNet.pnPlaces.finalCond, base_name = "ESN_QBFinalCond")
    end
    # # Final Condition Constraints on Engineering System Net Transitions
    if myLFES.hasProcessInitCond && myLFES.hasESN_Duration
        println("\t Building Engineering System Net Transition Final Conditions")
        @constraint(HFNMCF, QE[:, myLFES.simHorizon] .== myLFES.engSysNet.pnTransitions.finalCond, base_name = "ESN_QEFinalCond")
    end
    # # Capacity Constraint on Engineering System Net Places 
    if myLFES.hasBufferUpperBound
        println("\t Building Engineering System Net Place Capacity Constraints")
        @constraint(HFNMCF, QB[:,:] .<= myLFES.engSysNet.pnPlaces.upperBound, base_name = "ESN_QBUpperBound")
    end
    # # Capacity Constraint on Engineering System Net Transitions (UEneg)
    if myLFES.hasProcessUpperBound
        println("\t Building Engineering System Net Transition Capacity Constraint")
        idx = .!isEmpty.(myLFES.engSysNet.pnTransitions.upperBound)
        @constraint(HFNMCF, UEneg[idx,:] .<= myLFES.engSysNet.pnTransitions.upperBound[idx], base_name = "ESN_UEUpperBound")
    end

    # # Initial Conditions, Final Conditions, and Capacity Constraints on Operand Nets
    for l in 1:myLFES.operand.number
        # # Initial Condition Constraints on Operand Net Places
        if myLFES.operand.hasPlaceInitConds[l]
            println("\t Building Operand Net Number $l Initial Condition Place Constraints")
            @constraint(HFNMCF, QSL[l][:,1] .== myLFES.operand.pnPlaces[l].initCond, base_name = "OperandNet$(l)_QSLInitCond")
        end
        # # Initial Condition Constraints on Operand Net Transitions
        if myLFES.operand.hasTransitionInitConds[l] && myLFES.operand.hasOperandNet_Duration[l]
            println("\t Building Operand Net Number $l Initial Condition Transition Constraints")
            @constraint(HFNMCF, QEL[l][:,1] .== myLFES.operand.pnTransitions[l].initCond, base_name = "OperandNet$(l)_QELInitCond")
        end
        # # Final Condition Constraints on Operand Net Places
        if myLFES.operand.hasPlaceFinalConds[l]
            println("\t Building Operand Net Number $l Final Condition Place Constraints")
            @constraint(HFNMCF, QSL[l][:,myLFES.simHorizon] .== myLFES.operand.pnPlaces[l].finalCond, base_name = "OperandNet$(l)_QSLFinalCond")
        end
        # # Final Condition Constraints on Operand Net Transitions
        if myLFES.operand.hasTransitionFinalConds[l] && myLFES.operand.hasOperandNet_Duration[l]
            println("\t Building Operand Net Number $l Final Condition Transition Constraints")
            @constraint(HFNMCF, QEL[l][:,myLFES.simHorizon] .== myLFES.operand.pnTransitions[l].finalCond, base_name = "OperandNet$(l)_QSLFinalCond")
        end
        # # Capacity Constraint on Operand Net Places 
        if myLFES.operand.hasPlaceUpperBound[l]
            println("\t Building Operand Net Number $l Place Capacity Constraints")
            local idx 
            idx = .!isEmpty.(myLFES.operand.pnPlaces[l].upperBound)
            @constraint(HFNMCF, QSL[l][idx,:] .<= myLFES.operand.pnPlaces[l].upperBound[idx], base_name = "OperandNet$(l)_QSLUpperBound")
        end
    end

    # # Objective Function
    if myLFES.hasESN_STF1 && myLFES.hasBufferCost
        println("\t Building Objective Function -- Engineering System Net Buffer Costs")
        @expression(HFNMCF, fQB, sum(sum(myLFES.engSysNet.pnPlaces.linearCostCoeff .* QB)))
    else
        @expression(HFNMCF, fQB, 0)
    end
    if (myLFES.hasESN_STF1 || myLFES.hasESN_STF2) && myLFES.hasProcessCost
        println("\t Building Objective Function -- Engineering System Net Process Costs")
        @expression(HFNMCF, fUEneg, sum(sum(myLFES.engSysNet.pnTransitions.linearCostCoeff .* UEneg)))
    else
        @expression(HFNMCF, fUEneg, 0)
    end
    # Predefine container for expressions
    fQEL   = Vector{Any}(undef, myLFES.operand.number)
    fULneg = Vector{Any}(undef, myLFES.operand.number)
    for l in 1:myLFES.operand.number
        if myLFES.operand.hasOperandNet_STF1[l] && myLFES.operand.hasPlaceCost[l]
            println("\t Building Objective Function -- Operand Net Number $l Place Costs")
            fQEL[l] = @expression(HFNMCF, sum(sum(myLFES.operand.pnPlaces[l].linearCostCoeff .* QEL[l])))
        else
            fQEL[l] = @expression(HFNMCF, 0)
        end
        if (myLFES.operand.hasOperandNet_STF1[l] || myLFES.operand.hasOperandNet_STF2[l]) && myLFES.operand.hasTransitionCost[l]
            println("\t Building Objective Function -- Operand Net Number $l Transition Costs")
            fULneg[l] = @expression(HFNMCF, sum(sum(myLFES.operand.pnTransitions[l].linearCostCoeff .* ULneg[l])))
        else
            fULneg[l] = @expression(HFNMCF, 0)
        end
    end
    println("\t Building Complete Objective Function")
    @objective(HFNMCF, Min, fQB + fUEneg + sum(fQEL) + sum(fULneg))
    return HFNMCF, QB, QE, UEneg, UEpos, QSL, QEL, ULneg, ULpos
end

function visualizeHFNMCFProblem(HFNMCF)
    # # Visualization Optimization Program
    println("\n")
    println("Objective Function:  ")
    println(objective_function(HFNMCF))
    println("Constraints:")
    for c in all_constraints(HFNMCF,include_variable_in_set_constraints=false)
        println(c)
    end
end

function storeHFNMCFResults(myLFES, QB, QE, UEneg, UEpos, QSL, QEL, ULneg, ULpos)
        if myLFES.hasESN_STF1
        println("QB - Value of Engineering System Net Places:")
        display(cleanZeros(value.(QB)));
        myLFES.engSysNet.XS = sparseMat2MutableStruct(sparse(value.(QB)))
    end
    if myLFES.hasESN_STF2
        println("QE - Value of Engineering System Net Transitions:")
        display(value.(QE));
        myLFES.engSysNet.XE = sparseMat2MutableStruct(sparse(value.(QE)))
    end
    if myLFES.hasESN_STF1 || myLFES.hasESN_STF2
        println("UEneg - Value of Engineering System Net Transition Initiation:")
        display(value.(UEneg));
        myLFES.engSysNet.Uneg = sparseMat2MutableStruct(sparse(value.(UEneg)))
    end
    if (myLFES.hasESN_STF1 || myLFES.hasESN_STF2) && !all(isZero,myLFES.engSysNet.pnTransitions.duration)
        println("UEpos - Value of Engineering System Net Transition Termination:")
        display(value.(UEpos));
        myLFES.engSysNet.Upos = sparseMat2MutableStruct(sparse(value.(UEpos)))
    end
    for l in 1:myLFES.operand.number
        if myLFES.operand.hasOperandNet_STF1[l]
            println("QSL[$l] - Value of Operand Net Number $l Places:")
            display(convert.(Int64, value.(QSL[l])));
            myLFES.operand.XS[l] = sparseMat2MutableStruct(sparse(value.(QSL[l])))
        end
        if myLFES.operand.hasOperandNet_STF2[l]
            println("QEL[$l] Value of Operand Net Number $l Transitions:")
            display(convert.(Int64, value.(QEL[l])));
            myLFES.operand.XE[l] = sparseMat2MutableStruct(sparse(value.(QEL[l])))
        end
        if myLFES.operand.hasOperandNet_STF1[l] || myLFES.operand.hasOperandNet_STF2[l]
            println("ULneg[$l] - Value of Operand Net Number $l Transition Initiation:")
            display(convert.(Bool, value.(ULneg[l])));
            myLFES.operand.Uneg[l] = sparseMat2MutableStruct(sparse(value.(ULneg[l])))
            println("ULpos[$l] - Value of Operand Net Number $l Transition Termination:")
            display(convert.(Bool, value.(ULpos[l])));
            myLFES.operand.Upos[l] = sparseMat2MutableStruct(sparse(value.(ULpos[l])))
        end
    end
    myLFES.engSysNet.Mneg = sparseMat2MutableStruct(myLFES.engSysNet.Mneg)
    myLFES.engSysNet.Mpos = sparseMat2MutableStruct(myLFES.engSysNet.Mpos)
    myLFES.operand.Mneg = [sparseMat2MutableStruct(myLFES.operand.Mneg[l]) for l in 1:myLFES.operand.number]
    myLFES.operand.Mpos = [sparseMat2MutableStruct(myLFES.operand.Mpos[l]) for l in 1:myLFES.operand.number]
    myLFES.operand.syncMat = [sparseMat2MutableStruct(myLFES.operand.syncMat[l]) for l in 1:myLFES.operand.number]
    if myLFES.hasProcessCost
        myLFES.engSysNet.pnTransitions.linearCostCoeff = convertMatrix2VecOfVec(myLFES.engSysNet.pnTransitions.linearCostCoeff)
    end
    for l in 1:myLFES.operand.number
        if myLFES.operand.hasTransitionCost[l]
            myLFES.operand.pnTransitions[l].linearCostCoeff = convertMatrix2VecOfVec(myLFES.operand.pnTransitions[l].linearCostCoeff)
        end
    end
    return myLFES
end

function optHFNMCF(inputFilePath)
    myLFES = loadHFNMCFData(inputFilePath)

    ############ Start of JuMP Optimization #################
    HFNMCF, QB, QE, UEneg, UEpos, QSL, QEL, ULneg, ULpos = buildHFNMCFProblem(myLFES)

    if myLFES.verboseMode
        visualizeHFNMCFProblem(HFNMCF)
    end

    # # Solving HFNMCF Optimization Model
    println("\n")
    println("Solving HFNMCF Optimization Model")
    println("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    optimize!(HFNMCF)
    ############ End of Jump Optimization #################
    # # Reporting HFNMCF Optimization Model Solution
    println("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    println("\n")
    println(termination_status(HFNMCF))
    if termination_status(HFNMCF) != MOI.INFEASIBLE_OR_UNBOUNDED
        println("Optimal Value:  ",objective_value(HFNMCF))
        storeHFNMCFResults(myLFES, QB, QE, UEneg, UEpos, QSL, QEL, ULneg, ULpos)
    end

    ############ Saving Output Data #################
    JSON3.write(myLFES.juliaOutputFilePath, createJSON3(myLFES))
    return myLFES
end


export loadHFNMCFData, buildHFNMCFProblem, visualizeHFNMCFProblem, storeHFNMCFResults, createJSON3, optHFNMCF

############ Precompilation Workload #################
@setup_workload begin
    @compile_workload begin
        try
            optHFNMCF(tempname())
        catch
        end
    # println("precompilation workload!")
    # ############ Load Input Data #################
    # inputFilePath = "../3_PyHFGT_Output_Data/myLFES-RCPSP1-Renewable-Resources-defaultXML-2025-12-20.json".  #---> PLACEHOLDER. WE NEED A MORE FULL FEATURED SIMIPLE EXAMPLE
    # myLFES = loadHFNMCFData(inputFilePath)

    # ############ Start of JuMP Optimization #################
    # HFNMCF, QB, QE, UEneg, UEpos, QSL, QEL, ULneg, ULpos = buildHFNMCFProblem(myLFES)
    # if myLFES.verboseMode
    #     visualizeHFNMCFProblem(HFNMCF)
    # end
    # # Solving HFNMCF Optimization Model
    # println("\n")
    # println("Solving HFNMCF Optimization Model")
    # println("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    # optimize!(HFNMCF)
    # ############ End of Jump Optimization #################
    # # # Reporting HFNMCF Optimization Model Solution
    # println("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    # println("\n")
    # println(termination_status(HFNMCF))
    # if termination_status(HFNMCF) != MOI.INFEASIBLE_OR_UNBOUNDED
    #     println("Optimal Value:  ",objective_value(HFNMCF))
    #     storeHFNMCFResults(myLFES, QB, QE, UEneg, UEpos, QSL, QEL, ULneg, ULpos)
    # end
    # ############ Saving Output Data #################
    # JSON3.write(myLFES.juliaOutputFilePath, createJSON3(myLFES))
end
end

end # End of Module
