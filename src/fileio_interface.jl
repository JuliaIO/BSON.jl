#FileIO Interface
import FileIO

fileio_save(f::FileIO.File, doc::AbstractDict) = bson(FileIO.filename(f), doc)
fileio_save(s::FileIO.Stream, doc::AbstractDict) = bson(FileIO.stream(s), doc)
fileio_save(f, args::Pair...) = bson(f, Dict(args))

#This syntax is already in use to work with |> in FileIO
#fileio_save(f; kws...) = bson(f.filename, Dict(kws))

#function fileio_save(f, args...)
#    @assert length(args) % 2 ==0 "Mismatch between labels and data fields"
#    d = Dict(args[1:2:end] .=> args[2:2:end])
#    bson(f.filename, d)
#end

fileio_load(f::FileIO.File) = load(FileIO.filename(f))
fileio_load(s::FileIO.Stream) = load(FileIO.stream(s))

function fileio_load(f, args...)
    data = fileio_load(f)
    length(args) > 1 && return map( arg -> data[arg], args)
    return data[args[1]]
end
