module BaumWelchUtils
export force_pos_def, labels_to_gamma, gamma_to_labels, model_to_networks, mat_network_sparsity, sorted_edges, unique_by, states_to_networks, label_confusion_matrix, safe_mv_normal

using HMMTypes
using Distributions

function safe_mv_normal(mu :: Array{Float64},
                        cov :: Array{Float64, 2},
                        check_singular = false)
    try
        if (check_singular && det(10000*cov) == 0)
            println("Singular matrix encountered. Sample not long enough.")
            println("Temporarily using identity cov.")
            cov = eye(size(cov,1))
        end

        MvNormal(vec(mu), cov)
    catch e
        cov_ = force_pos_def(cov)
        try
            MvNormal(vec(mu), cov_)
        catch e2
            throw(e2)
        end
    end
end

function label_confusion_matrix(found_labels, found_k,
                                true_labels, true_k)
    label_confusion_matrix = zeros(Int32, found_k, true_k)
    for label_pair = zip(found_labels, true_labels)
        label_confusion_matrix[label_pair...] += 1
    end
    label_confusion_matrix
end

function unique_by(vec,
                    by)
    results = typeof(vec[1])[]
    by_set = Set()

    for v = vec
        b = by(v)
        if !in(b, by_set)
            push!(by_set, b)
            push!(results, v)
        end
    end

    results
end

function force_pos_def(m)
    if(!isposdef(m))
        m = (m + m') / 2
        for i = 1:5
            if (!isposdef(m))
                m += - eye(size(m, 1)) * (minimum(eig(m)[1]) - 10e-10)
            else
                return m
            end
        end
    else
        return m
    end

    error("can't force pos def. eigs are ", eig(m)[1])
end

function labels_to_gamma(labels, k)
    n = length(labels)
    gamma = zeros(k, n)
    for i = 1:k
        gamma[i, labels .== i] = 1
    end
    gamma
end

function gamma_to_labels(gamma)
    n = size(gamma, 2)
    [indmax(gamma[:, i]) for i = 1:n]
end

function model_to_networks(model :: HMMStateModel)
    states_to_networks(model.states)
end

function states_to_networks(states :: Array{HMMState, 1})
    [state.active ?
     inv(cholfact(cov(state.dist))) :
     Void
     for state = states]
end

## Transpose ##
const transposebaselength=64
function transpose!(B::StridedMatrix,A::StridedMatrix)
    m, n = size(A)
    size(B,1) == n && size(B,2) == m || throw(DimensionMismatch("transpose"))

    if m*n<=4*transposebaselength
        @inbounds begin
            for j = 1:n
                for i = 1:m
                    B[j,i] = transpose(A[i,j])
                end
            end
        end
    else
        transposeblock!(B,A,m,n,0,0)
    end
    return B
end
function transpose!(B::StridedVector, A::StridedMatrix)
    length(B) == length(A) && size(A,1) == 1 || throw(DimensionMismatch("transpose"))
    copy!(B, A)
end
function transpose!(B::StridedMatrix, A::StridedVector)
    length(B) == length(A) && size(B,1) == 1 || throw(DimensionMismatch("transpose"))
    copy!(B, A)
end
function transposeblock!(B::StridedMatrix,A::StridedMatrix,m::Int,n::Int,offseti::Int,offsetj::Int)
    if m*n<=transposebaselength
        @inbounds begin
            for j = offsetj+(1:n)
                for i = offseti+(1:m)
                    B[j,i] = transpose(A[i,j])
                end
            end
        end
    elseif m>n
        newm=m>>1
        transposeblock!(B,A,newm,n,offseti,offsetj)
        transposeblock!(B,A,m-newm,n,offseti+newm,offsetj)
    else
        newn=n>>1
        transposeblock!(B,A,m,newn,offseti,offsetj)
        transposeblock!(B,A,m,n-newn,offseti,offsetj+newn)
    end
    return B
end

function mat_network_sparsity(mat, eps = 1e-8)
    m = size(mat, 1)

    off_diags = 1 - eye(m)
    off_diag_mat = mat .* off_diags

    non_zeros = mat .> eps

    total_size = length(mat) - m

    sum(non_zeros) / total_size
end

end
