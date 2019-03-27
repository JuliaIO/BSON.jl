#FileIO Interface

fileio_save(f, doc::AbstractDict) = bson(f.filename, doc)
fileio_save(f, args::Pair...) = bson(f.filename, Dict(args))

#This syntax is already in use to work with |> in FileIO
#fileio_save(f; kws...) = bson(f.filename, Dict(kws))

#function fileio_save(f, args...)
#    @assert length(args) % 2 ==0 "Mismatch between labels and data fields"
#    d = Dict(args[1:2:end] .=> args[2:2:end])
#    bson(f.filename, d)
#end

fileio_load(f) = load(f.filename)

function fileio_load(f, args...)
    data = load(f.filename)
    length(args) > 1 && return map( arg -> data[arg], args)
    return data[args[1]]
end
