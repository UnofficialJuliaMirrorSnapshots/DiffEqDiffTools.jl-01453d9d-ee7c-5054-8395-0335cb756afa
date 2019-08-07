mutable struct JacobianCache{CacheType1,CacheType2,CacheType3,ColorType,SparsityType,fdtype,returntype,inplace}
    x1  :: CacheType1
    fx  :: CacheType2
    fx1 :: CacheType3
    colorvec :: ColorType
    sparsity :: SparsityType
end

function JacobianCache(
    x,
    fdtype     :: Type{T1} = Val{:forward},
    returntype :: Type{T2} = eltype(x),
    inplace    :: Type{Val{T3}} = Val{true};
    colorvec = eachindex(x),
    sparsity = nothing) where {T1,T2,T3}

    if eltype(x) <: Real && fdtype==Val{:complex}
        x1  = false .* im .* x
        _fx = false .* im .* x
    else
        x1 = copy(x)
        _fx = copy(x)
    end

    if fdtype==Val{:complex}
        _fx1  = nothing
    else
        _fx1 = copy(x)
    end

    JacobianCache(x1,_fx,_fx1,fdtype,returntype,inplace;colorvec=colorvec,sparsity=sparsity)
end

function JacobianCache(
    x ,
    fx,
    fdtype     :: Type{T1} = Val{:forward},
    returntype :: Type{T2} = eltype(x),
    inplace    :: Type{Val{T3}} = Val{true};
    colorvec = eachindex(x),
    sparsity = nothing) where {T1,T2,T3}

    if eltype(x) <: Real && fdtype==Val{:complex}
        x1  = false .* im .* x
    else
        x1 = copy(x)
    end

    if eltype(fx) <: Real && fdtype==Val{:complex}
        _fx = false .* im .* fx
    else
        _fx = copy(fx)
    end

    if fdtype==Val{:complex}
        _fx1  = nothing
    else
        _fx1 = copy(fx)
    end

    JacobianCache(x1,_fx,_fx1,fdtype,returntype,inplace;colorvec=colorvec,sparsity=sparsity)
end

function JacobianCache(
    x1 ,
    fx ,
    fx1,
    fdtype     :: Type{T1} = Val{:forward},
    returntype :: Type{T2} = eltype(fx),
    inplace    :: Type{Val{T3}} = Val{true};
    colorvec = 1:length(x1),
    sparsity = nothing) where {T1,T2,T3}

    if fdtype==Val{:complex}
        !(returntype<:Real) && fdtype_error(returntype)

        if eltype(fx) <: Real
            _fx  = false .* im .* fx
        else
            _fx = fx
        end
        if eltype(x1) <: Real
            _x1  = false .* im .* x1
        else
            _x1 = x1
        end
    else
        _x1 = x1
        @assert eltype(fx) == T2
        @assert eltype(fx1) == T2
        _fx = fx
    end
    JacobianCache{typeof(_x1),typeof(_fx),typeof(fx1),typeof(colorvec),typeof(sparsity),fdtype,returntype,inplace}(_x1,_fx,fx1,colorvec,sparsity)
end

function finite_difference_jacobian!(J::AbstractMatrix,
    f,
    x::AbstractArray{<:Number},
    fdtype     :: Type{T1}=Val{:forward},
    returntype :: Type{T2}=eltype(x),
    inplace    :: Type{Val{T3}}=Val{true},
    f_in       :: Union{T2,Nothing}=nothing;
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep,
    colorvec = eachindex(x),
    sparsity = ArrayInterface.has_sparsestruct(J) ? J : nothing) where {T1,T2,T3}

    cache = JacobianCache(x, fdtype, returntype, inplace)
    finite_difference_jacobian!(J, f, x, cache, f_in; relstep=relstep, absstep=absstep, colorvec=colorvec, sparsity=sparsity)
end

function finite_difference_jacobian(f, x::AbstractArray{<:Number},
    fdtype     :: Type{T1}=Val{:forward},
    returntype :: Type{T2}=eltype(x),
    inplace    :: Type{Val{T3}}=Val{true},
    f_in       :: Union{T2,Nothing}=nothing;
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep,
    colorvec = eachindex(x),
    sparsity = nothing,
    dir=true) where {T1,T2,T3}

    cache = JacobianCache(x, fdtype, returntype, inplace)
    finite_difference_jacobian(f, x, cache, f_in; relstep=relstep, absstep=absstep, colorvec=colorvec, sparsity=sparsity, dir=dir)
end

function finite_difference_jacobian(
    f,
    x,
    cache::JacobianCache{T1,T2,T3,cType,sType,fdtype,returntype,inplace},
    f_in=nothing;
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep,
    colorvec = cache.colorvec,
    sparsity = cache.sparsity,
    dir=true) where {T1,T2,T3,cType,sType,fdtype,returntype,inplace}
    _J = false .* x .* x'
    _J isa SMatrix ? J = MArray(_J) : J = _J
    finite_difference_jacobian!(J, f, x, cache, f_in; relstep=relstep, absstep=absstep, colorvec=colorvec, sparsity=sparsity, dir=dir)
    _J isa SMatrix ? SArray(J) : J
end

function finite_difference_jacobian!(
    J::AbstractMatrix{<:Number},
    f,
    x::AbstractArray{<:Number},
    cache::JacobianCache{T1,T2,T3,cType,sType,fdtype,returntype,inplace},
    f_in::Union{T2,Nothing}=nothing;
    relstep = default_relstep(fdtype, eltype(x)),
    absstep=relstep,
    colorvec = cache.colorvec,
    sparsity::Union{AbstractArray,Nothing} = cache.sparsity,
    dir = true) where {T1,T2,T3,cType,sType,fdtype,returntype,inplace}

    m, n = size(J)
    _color = reshape(colorvec,size(x)...)

    x1, fx, fx1 = cache.x1, cache.fx, cache.fx1
    if inplace == Val{true}
        copyto!(x1, x)
    end
    vfx = vec(fx)

    if ArrayInterface.has_sparsestruct(sparsity)
        rows_index, cols_index = ArrayInterface.findstructralnz(sparsity)
    end

    if sparsity !== nothing
        fill!(J,false)
    end

    if fdtype == Val{:forward}
        vfx1 = vec(fx1)

        if f_in isa Nothing
            if inplace == Val{true}
                f(fx, x)
            else
                fx = f(x)
                vfx = vec(fx)
            end
        else
            vfx = vec(f_in)
        end

        @inbounds for color_i ∈ 1:maximum(colorvec)

            if colorvec isa Base.OneTo || colorvec isa UnitRange || colorvec isa StaticArrays.SOneTo # Dense matrix
                x1_save = ArrayInterface.allowed_getindex(x1,color_i)
                epsilon = compute_epsilon(Val{:forward}, x1_save, relstep, absstep, dir)
                if inplace == Val{true}
                    ArrayInterface.allowed_setindex!(x1,x1_save + epsilon,color_i)
                else
                    _x1 = Base.setindex(x1,x1_save+epsilon,color_i)
                end
            else # Perturb along the colorvec vector
                @. fx1 = x1 * (_color == color_i)
                tmp = norm(fx1)
                epsilon = compute_epsilon(Val{:forward}, sqrt(tmp), relstep, absstep, dir)

                if inplace == Val{true}
                    @. x1 = x1 + epsilon * (_color == color_i)
                else
                    _x1 = @. _x1 + epsilon * (_color == color_i)
                end
            end

            if inplace == Val{true}
                f(fx1, x1)

                if sparsity isa Nothing
                    # J is dense, so either it is truly dense or this is the
                    # compressed form of the coloring, so write into it.
                    @. J[:,color_i] = (vfx1 - vfx) / epsilon
                else
                    # J is a sparse matrix, so decompress on the fly
                    @. vfx1 = (vfx1 - vfx) / epsilon

                    if ArrayInterface.fast_scalar_indexing(x1)
                        for i in 1:length(cols_index)
                            if colorvec[cols_index[i]] == color_i
                                if J isa SparseMatrixCSC
                                    J.nzval[i] = vfx1[rows_index[i]]
                                else
                                    J[rows_index[i],cols_index[i]] = vfx1[rows_index[i]]
                                end
                            end
                        end
                    else
                        #=
                        J.nzval[rows_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        or
                        J[rows_index, cols_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        += means requires a zero'd out start
                        =#
                        if J isa SparseMatrixCSC
                            @. setindex!((J.nzval,),getindex((J.nzval,),rows_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index)
                        else
                            @. setindex!((J,),getindex((J,),rows_index, cols_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index, cols_index)
                        end
                    end
                end
            else
                fx1 = f(_x1)
                vfx1 = vec(fx1)
                if sparsity isa Nothing
                    # J is dense, so either it is truly dense or this is the
                    # compressed form of the coloring, so write into it.
                    J[:,color_i] = (vfx1 - vfx) / epsilon
                else
                    # J is a sparse matrix, so decompress on the fly
                    _vfx1 = (vfx1 - vfx) / epsilon

                    if ArrayInterface.fast_scalar_indexing(x1)
                        for i in 1:length(cols_index)
                            if colorvec[cols_index[i]] == color_i
                                if J isa SparseMatrixCSC
                                    J.nzval[i] = vfx1[rows_index[i]]
                                else
                                    J[rows_index[i],cols_index[i]] = vfx1[rows_index[i]]
                                end
                            end
                        end
                    else
                        #=
                        J.nzval[rows_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        or
                        J[rows_index, cols_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        += means requires a zero'd out start
                        =#
                        if J isa SparseMatrixCSC
                            @. setindex!((J.nzval,),getindex((J.nzval,),rows_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index)
                        else
                            @. setindex!((J,),getindex((J,),rows_index, cols_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index, cols_index)
                        end
                    end
                end
            end

            # Now return x1 back to its original value
            if inplace == Val{true}
                if colorvec isa Base.OneTo || colorvec isa UnitRange || colorvec isa StaticArrays.SOneTo #Dense matrix
                    ArrayInterface.allowed_setindex!(x1,x1_save,color_i)
                else
                    @. x1 = x1 - epsilon * (_color == color_i)
                end
            end

        end #for ends here
    elseif fdtype == Val{:central}
        vfx1 = vec(fx1)

        @inbounds for color_i ∈ 1:maximum(colorvec)

            if colorvec isa Base.OneTo || colorvec isa UnitRange || colorvec isa StaticArrays.SOneTo # Dense matrix
                x_save = ArrayInterface.allowed_getindex(x,color_i)
                x1_save = ArrayInterface.allowed_getindex(x1,color_i)
                epsilon = compute_epsilon(Val{:central}, x_save, relstep, absstep, dir)
                if inplace == Val{true}
                    ArrayInterface.allowed_setindex!(x1,x1_save+epsilon,color_i)
                    ArrayInterface.allowed_setindex!(x,x_save-epsilon,color_i)
                else
                    _x1 = Base.setindex(x1,x1_save+epsilon,color_i)
                    _x  = Base.setindex(x, x_save-epsilon, color_i)
                end
            else # Perturb along the colorvec vector
                @. fx1 = x1 * (_color == color_i)
                tmp = norm(fx1)
                epsilon = compute_epsilon(Val{:central}, sqrt(tmp), relstep, absstep, dir)
                if inplace == Val{true}
                    @. x1 = x1 + epsilon * (_color == color_i)
                    @. x  = x  - epsilon * (_color == color_i)
                else
                    _x1 = @. _x1 + epsilon * (_color == color_i)
                    _x  = @. _x  - epsilon * (_color == color_i)
                end
            end

            if inplace == Val{true}
                f(fx1, x1)
                f(fx, x)

                if sparsity isa Nothing
                    # J is dense, so either it is truly dense or this is the
                    # compressed form of the coloring, so write into it.
                    @. J[:,color_i] = (vfx1 - vfx) / 2epsilon
                else
                    # J is a sparse matrix, so decompress on the fly
                    @. vfx1 = (vfx1 - vfx) / 2epsilon

                    if ArrayInterface.fast_scalar_indexing(x1)
                        for i in 1:length(cols_index)
                            if colorvec[cols_index[i]] == color_i
                                if J isa SparseMatrixCSC
                                    J.nzval[i] = vfx1[rows_index[i]]
                                else
                                    J[rows_index[i],cols_index[i]] = vfx1[rows_index[i]]
                                end
                            end
                        end
                    else
                        #=
                        J.nzval[rows_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        or
                        J[rows_index, cols_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        += means requires a zero'd out start
                        =#
                        if J isa SparseMatrixCSC
                            @. setindex!((J.nzval,),getindex((J.nzval,),rows_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index)
                        else
                            @. setindex!((J,),getindex((J,),rows_index, cols_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index, cols_index)
                        end
                    end
                end

            else
                fx1 = f(_x1)
                fx = f(_x)
                vfx1 = vec(fx1)
                vfx  = vec(fx)

                if sparsity isa Nothing
                    # J is dense, so either it is truly dense or this is the
                    # compressed form of the coloring, so write into it.
                    J[:,color_i] = (vfx1 - vfx) / 2epsilon
                else
                    # J is a sparse matrix, so decompress on the fly
                    vfx1 = (vfx1 - vfx) / 2epsilon
                    # vfx1 is the compressed Jacobian column

                    if ArrayInterface.fast_scalar_indexing(x1)
                        for i in 1:length(cols_index)
                            if colorvec[cols_index[i]] == color_i
                                if J isa SparseMatrixCSC
                                    J.nzval[i] = vfx1[rows_index[i]]
                                else
                                    J[rows_index[i],cols_index[i]] = vfx1[rows_index[i]]
                                end
                            end
                        end
                    else
                        #=
                        J.nzval[rows_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        or
                        J[rows_index, cols_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        += means requires a zero'd out start
                        =#
                        if J isa SparseMatrixCSC
                            @. setindex!((J.nzval,),getindex((J.nzval,),rows_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index)
                        else
                            @. setindex!((J,),getindex((J,),rows_index, cols_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index, cols_index)
                        end
                    end
                end
            end

            # Now return x1 back to its original value
            if inplace == Val{true}
                if colorvec isa Base.OneTo || colorvec isa UnitRange || colorvec isa StaticArrays.SOneTo #Dense matrix
                    ArrayInterface.allowed_setindex!(x1,x1_save,color_i)
                    ArrayInterface.allowed_setindex!(x,x_save,color_i)
                else
                    @. x1 = x1 - epsilon * (_color == color_i)
                    @. x  = x  + epsilon * (_color == color_i)
                end
            end
        end
    elseif fdtype==Val{:complex} && returntype<:Real
        epsilon = eps(eltype(x))
        @inbounds for color_i ∈ 1:maximum(colorvec)

            if colorvec isa Base.OneTo || colorvec isa UnitRange || colorvec isa StaticArrays.SOneTo # Dense matrix
                x1_save = ArrayInterface.allowed_getindex(x1,color_i)
                if inplace == Val{true}
                    ArrayInterface.allowed_setindex!(x1,x1_save + im*epsilon, color_i)
                else
                    _x1 = setindex(x1,x1_save+im*epsilon,color_i)
                end
            else # Perturb along the colorvec vector
                if inplace == Val{true}
                    @. x1 = x1 + im * epsilon * (_color == color_i)
                else
                    _x1 = @. x1 + im * epsilon * (_color == color_i)
                end
            end

            if inplace == Val{true}
                f(fx,x1)
                if sparsity isa Nothing
                    # J is dense, so either it is truly dense or this is the
                    # compressed form of the coloring, so write into it.
                    @. J[:,color_i] = imag(vfx) / epsilon
                else
                    # J is a sparse matrix, so decompress on the fly
                    @. vfx = imag(vfx) / epsilon

                    if ArrayInterface.fast_scalar_indexing(x1)
                        for i in 1:length(cols_index)
                            if colorvec[cols_index[i]] == color_i
                                if J isa SparseMatrixCSC
                                    J.nzval[i] = vfx[rows_index[i]]
                                else
                                    J[rows_index[i],cols_index[i]] = vfx[rows_index[i]]
                                end
                            end
                        end
                    else
                        #=
                        J.nzval[rows_index] .+= (colorvec[cols_index] .== color_i) .* vfx[rows_index]
                        or
                        J[rows_index, cols_index] .+= (colorvec[cols_index] .== color_i) .* vfx[rows_index]
                        += means requires a zero'd out start
                        =#
                        if J isa SparseMatrixCSC
                            @. setindex!((J.nzval,),getindex((J.nzval,),rows_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx,),rows_index),rows_index)
                        else
                            @. setindex!((J,),getindex((J,),rows_index, cols_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx,),rows_index),rows_index, cols_index)
                        end
                    end
                end

            else
                fx = f(_x1)
                vfx = vec(fx)
                if sparsity isa Nothing
                    # J is dense, so either it is truly dense or this is the
                    # compressed form of the coloring, so write into it.
                    J[:,color_i] = imag(vfx) / epsilon
                else
                    # J is a sparse matrix, so decompress on the fly
                    vfx = imag(vfx) / epsilon

                    if ArrayInterface.fast_scalar_indexing(x1)
                        for i in 1:length(cols_index)
                            if colorvec[cols_index[i]] == color_i
                                if J isa SparseMatrixCSC
                                    J.nzval[i] = vfx1[rows_index[i]]
                                else
                                    J[rows_index[i],cols_index[i]] = vfx1[rows_index[i]]
                                end
                            end
                        end
                    else
                        #=
                        J.nzval[rows_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        or
                        J[rows_index, cols_index] .+= (colorvec[cols_index] .== color_i) .* vfx1[rows_index]
                        += means requires a zero'd out start
                        =#
                        if J isa SparseMatrixCSC
                            @. setindex!((J.nzval,),getindex((J.nzval,),rows_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index)
                        else
                            @. setindex!((J,),getindex((J,),rows_index, cols_index) + (getindex((_color,),cols_index) == color_i) * getindex((vfx1,),rows_index),rows_index, cols_index)
                        end
                    end
                end
            end

            if inplace == Val{true}
                # Now return x1 back to its original value
                if colorvec isa Base.OneTo || colorvec isa UnitRange || colorvec isa StaticArrays.SOneTo
                    ArrayInterface.allowed_setindex!(x1,x1_save,color_i)
                else
                    @. x1 = x1 - im * epsilon * (_color == color_i)
                end
            end
        end
    else
        fdtype_error(returntype)
    end
    J
end

function resize!(cache::JacobianCache, i::Int)
    resize!(cache.x1,  i)
    resize!(cache.fx,  i)
    cache.fx1 != nothing && resize!(cache.fx1, i)
    cache.colorvec = 1:i
    nothing
end
