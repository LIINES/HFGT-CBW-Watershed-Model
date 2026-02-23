include("read_names.jl")

# Master function to build the LFES
function load_lfes_from_hdf5(filepath::String)
    h5open(filepath, "r") do f
        numOperands = read_scalar_int(f, "outputData/value/operandNumber/value")
        numBuffers = read_scalar_int(f, "outputData/value/bufferNumber/value")
        bufferName = read_name_dict(f, "outputData/value/bufferName/value")

        # Read raw COO matrices
        MRho2Pos = read_coo_matrix(f, "outputData/value/engSysNetMpos/value")
        MRho2Neg = read_coo_matrix(f, "outputData/value/engSysNetMneg/value")

        # Convert to sparse matrices
        incMatPlus = coo_to_sparse(MRho2Pos)
        incMatMinus_raw = coo_to_sparse(MRho2Neg)

        # Identify shared nonzero entries between Plus and Minus
        # shared_entries = (incMatPlus .!= 0) .& (incMatMinus_raw .!= 0)

        # Set shared entries to 0 in the negative matrix
        incMatMinus = copy(incMatMinus_raw)
        # incMatMinus[shared_entries] .= 0.0

        # Continue with constructing incMat and the LFES struct
        incMat = incMatPlus - incMatMinus

        numBufferOperandPairs = size(incMat, 1)
        numCapabilities = read_scalar_int(f, "outputData/value/DOFS/value")

        engSysNetTransitions = read_name_dict(f, "outputData/value/engSysNetTransitions/value")
        engSysNetPlaces = read_name_dict(f, "outputData/value/engSysNetPlaces/value")
        transformationResourceName = read_name_dict(f, "outputData/value/transformationResourceName/value")
        transformationResourceRiverSegment = read_name_dict(f, "outputData/value/transformationResourceRiverSegment/value")
        transformationResourceCounty = read_name_dict(f, "outputData/value/transformationResourceCounty/value")
        transformationResourceState = read_name_dict(f, "outputData/value/transformationResourceState/value")
        idxCapability = Int.(vec(read(f, "outputData/value/idxCapability/value")))
        idxCapabilityResource = Int.(vec(read(f, "outputData/value/idxCapabilityResource/value")))
        idxCapabilityProcess = Int.(vec(read(f, "outputData/value/idxCapabilityProcess/value")))
        idxResource = Int.(vec(read(f, "outputData/value/idxResource/value")))
        idxTransformationResourceResource = Int.(vec(read(f, "outputData/value/idxTransformationResourceResource/value")))
        resourceName =  read_name_dict(f, "outputData/value/resourceName/value")
        idxOriginTransportProcess = Int.(vec(read(f, "outputData/value/idxOriginTransportProcess/value")))
        idxDestinationTransportProcess = Int.(vec(read(f, "outputData/value/idxDestinationTransportProcess/value")))
        refTransportProcess = read_name_dict(f, "outputData/value/refTransportProcess/value")
        idxProcessTransportProcess = Int.(vec(read(f, "outputData/value/idxProcessTransportProcess/value")))

        return LFES(
        numOperands,
        numBuffers,
        bufferName,
        incMatPlus,
        incMatMinus,
        incMat,
        numBufferOperandPairs,
        numCapabilities,
        engSysNetTransitions,
        engSysNetPlaces,
        transformationResourceName,
        transformationResourceRiverSegment,
        transformationResourceCounty,
        transformationResourceState,
        idxCapability,
        idxCapabilityResource,
        idxCapabilityProcess,
        idxResource,
        idxTransformationResourceResource,
        resourceName,
        idxOriginTransportProcess,
        idxDestinationTransportProcess,
        refTransportProcess,
        idxProcessTransportProcess
    )
    end
end