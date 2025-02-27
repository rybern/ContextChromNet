module SyntheticData

export rand_HMM_model, rand_HMM_data

using HMMTypes
using EmissionDistributions

using Distributions
using StatsBase
using Memoize

# TODO: CHANGE SPARSITY TO DENSITY!
function rand_HMM_model(p :: Integer,
                        k :: Integer;
                        mean_range = .1,
                        density = .3,
                        shape = 30,
                        dwell_prob = 3/4)
    dists = Array(MvNormal, k)
    for i = 1:k
        mu = rand(p) * mean_range - mean_range/2;
        cov = rand_cov(p, density, shape)

        dists[i] = MvNormal(mu, cov)
    end

    states = map(dist -> HMMState(dist, true), dists)
    HMMStateModel(states, uniform_trans(k, dwell_prob))
end

function rand_HMM_data(n :: Integer,
                       p :: Integer,
                       k :: Integer,
                       model_generator = rand_HMM_model :: Function;
                       starting_distribution = Void,
                       sample = state_sample)
    model = model_generator(p, k)

    if starting_distribution == Void
        starting_distribution = vec(sum(model.trans, 2))
    end

    rand_HMM_data(n, p,
                  model;
                  starting_distribution = starting_distribution,
                  sample = state_sample)
end

function rand_HMM_data(n :: Integer,
                       p :: Integer,
                       model :: HMMStateModel;
                       starting_distribution = vec(sum(model.trans, 2)),
                       sample = state_sample)
    data = Array(Float64, p, n)

    labels = sample_label_series(n, model.trans, starting_distribution)

    for i = 1:n
        data[:, i] = sample(model.states[labels[i]]);
    end

    (data, labels, model)
end

function sample_label_series(n :: Integer,
                             trans :: Array{Float64, 2},
                             init :: Array{Float64, 1})
    init = init / sum(init)
    initial_state = rand(Categorical(init))
    sample_label_series(n, trans, initial_state)
end

function sample_label_series(n :: Integer,
                             trans :: Array{Float64, 2},
                             init :: Integer = 1)
    k = size(trans,1)
    dists = Array(Categorical, k)
    for i = 1:k
        dists[i] = Categorical(vec(trans[i, :]))
    end

    labels = Array(Int64, n)

    state = init
    for i = 1:n
        labels[i] = state;
        state = rand(dists[state]);
    end

    labels
end


function uniform_trans(k, prop)
    eye(k) * prop + ((1 - prop) / (k - 1)) * (ones(k, k) - eye(k));
end

function rand_cov(p)
    inv(cholfact(randInvcov(p)))
end

#found in GaussianMixtures, should produce a PSD matrix
function randInvcov(p)
    T = rand(p, p)
    inv(cholfact(T' * T / p))
end

# From Scott. Thanks Scott!
function rand_cov_old(K, netDensity)
    IC = diagm(abs(randn(K)))
    for i in 1:K, j in 1:i-1
        IC[i,j] = rand() < netDensity ? rand()-1.01 : 0.0
        IC[j,i] = IC[i,j]
    end
    mineval = minimum(eig(IC)[1])
    if mineval < 0
        IC -= eye(K)*mineval*1.01
    end
    C = inv(IC)
#    Base.cov2cor!(C, sqrt(diag(C)))
end

function zero_rand_offdiag_pairs!(m, num_pairs_to_zero)
    indices = filter(t -> t[2] < t[1], [(i, j) for i = 1:size(m, 1), j = 1:size(m, 2)])
    ixs_to_zero = sample(indices, num_pairs_to_zero, replace=false)
    for (i, j) = ixs_to_zero
        m[i, j] = 0.0;
        m[j, i] = 0.0;
    end
end

# From Scott. Thanks Scott!
function rand_cov(n, net_density, cond_number)
    IC = diagm(abs(randn(n)))
    for i = 1:n
        for j = 1:i
            IC[i, j] = rand()
            IC[j, i] = IC[i, j]
        end
    end

    num_to_zero = round(Int, (n * n - n) * (1 - net_density) / 2.0)
    zero_rand_offdiag_pairs!(IC, num_to_zero)

    mineval = minimum(eig(IC)[1])
    if mineval < 0
        IC -= eye(n)*mineval*1.01
    end

    IC_cond = set_cond_number(IC, cond_number)

    C = inv(cholfact(IC_cond))
#    Base.cov2cor!(C, sqrt(diag(C)))
end

function set_cond_number(m, c)
    svs = svd(m)[2]
    min_sv = svs[end]
    max_sv = svs[1]

    cs = c*c
    d = (c * min_sv - max_sv) / (1 - c)

    m + d * eye(size(m, 1))
end

function cov_network_density(m; eps = 1e-8)
    im = inv(cholfact(m))
    p = size(m, 1)
    num_nonzero = length(filter(x -> abs(x) > eps, im + eye(p)))
    (num_nonzero-p) / (p*p-p)
end

function rand_cov_(p, density)
    #generate 30 psd matricies with aprox. correct sparsities
    aprox_invcovs = [aprox_sparse_psd_matrix(p, density) for i = 1:30]

    # measure closeness to desired density
    density_errors = map(m -> abs(density - mat_density(m)), aprox_invcovs)

    # return inverse of closest
    closest_invcov = aprox_invcovs[indmin(density_errors)]
    B = inv(cholfact(closest_invcov))
    normalize_determinant(B)
end

function normalize_determinant(m :: Array{Float64, 2}, to = 1)
    c = (to/det(m))^(1/size(m, 1))
    c * m
end

function aprox_sparse_psd_matrix(p, density)
    generator = () -> rand(p, p)
    p_density = 1 - sqrt(density / p)
    P = sparsify_rand(generator, p_density, X -> rank(X) == p)
    P' * P
end

function sparsify_rand(generator, sparify, valid)
    result = false

    while result == false
        M = generator()
        result = sparsify_mat(m, density, valid)
    end

    result
end

# TODO only measure density of off-diags
@memoize function sparsify_mat(m, density, valid)
    p = size(m, 1)
    s = p * p - p;
    nzeros = s * density;

    for i = 1:nzeros/2
        m = zero_rand_offdiag(m, valid);
        if (m == false)
            return false
        end
    end

    m
end

function sparsify_rand(generator, density, valid)
    M = generator()

    s = size(M)[1] * size(M)[2];
    nzeros = s * density;

    for i = 1:nzeros/2
        M = zero_rand_offdiag(M, valid);
        if(M == false)
            return sparsify_rand(generator, density, valid);
        end
    end

    M
end

function zero_rand_offdiag(M, valid = isposdef)
    (n, m) = size(M);

    for i = shuffle(collect(1:n))
        for j = shuffle(collect(1:(i-1)))
            if (M[i, j] == 0)
                continue
            end

            temp = M[i, j]

            M[i, j] = 0.0;
            M[j, i] = 0.0;

            if(valid(M))
                return M
            else
                M[i, j] = temp
                M[j, i] = temp
            end
        end
    end

    return false
end

end
