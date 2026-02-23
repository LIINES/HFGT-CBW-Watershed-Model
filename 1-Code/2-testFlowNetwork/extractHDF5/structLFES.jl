# Define struct to hold LFES data
struct LFES
    numOperands::Int
    numBuffers::Int
    bufferName::Vector{String}
    incMatPlus::SparseMatrixCSC{Float64, Int}
    incMatMinus::SparseMatrixCSC{Float64, Int}
    incMat::SparseMatrixCSC{Float64, Int}
    numBufferOperandPairs::Int
    numCapabilities::Int
    engSysNetTransitions::Vector{String}
    engSysNetPlaces::Vector{String}
    transformationResourceName::Vector{String}
    transformationResourceRiverSegment::Vector{String}
    transformationResourceCounty::Vector{String}
    transformationResourceState::Vector{String}
    idxCapability::Vector{Int}
    idxCapabilityResource::Vector{Int}
    idxCapabilityProcess::Vector{Int}
    idxResource::Vector{Int}
    idxTransformationResourceResource::Vector{Int}
    resourceName::Vector{String}
    idxOriginTransportProcess::Vector{Int}
    idxDestinationTransportProcess::Vector{Int}
    refTransportProcess::Vector{String}
    idxProcessTransportProcess::Vector{Int}
end