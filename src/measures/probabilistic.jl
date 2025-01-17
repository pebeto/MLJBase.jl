const DOC_DISTRIBUTIONS =
"""
In the case the predictions `ŷ` are continuous probability
distributions, such as `Distributions.Normal`, replace the above sum
with an integral, and interpret `p` as the probablity density
function. In case of discrete distributions over the integers, such as
`Distributions.Poisson`, sum over all integers instead of `C`.
"""
const WITH_L2NORM_CONTINUOUS =
    [@eval(Distributions.$d) for d in [
        :Chisq,
        :Gamma,
        :Beta,
        :Chi,
        :Cauchy,
        :Normal,
        :Uniform,
        :Logistic,
        :Exponential]]

const WITH_L2NORM_COUNT =
    [@eval(Distributions.$d) for d in [
        :Poisson,
        :DiscreteUniform,
        :DiscreteNonParametric]]

const WITH_L2NORM = vcat([UnivariateFinite, ],
                         WITH_L2NORM_CONTINUOUS,
                         WITH_L2NORM_COUNT)

const UD = Distributions.UnivariateDistribution

# ========================================================
# AGGREGATED MEASURES

# ---------------------------------------------------------
# AreaUnderCurve

# Implementation based on the Mann-Whitney U statistic.
# see https://en.wikipedia.org/wiki/Receiver_operating_characteristic#Area_under_the_curve
# and https://en.wikipedia.org/wiki/Mann%E2%80%93Whitney_U_test#Area_under_curve_(AUC)_statistic_for_ROC_curves


struct AreaUnderCurve <: Aggregated end

metadata_measure(AreaUnderCurve;
                 human_name = "area under the ROC",
                 instances = ["area_under_curve", "auc"],
                 target_scitype           = FiniteArrMissing{2},
                 prediction_type          = :probabilistic,
                 orientation              = :score,
                 supports_weights         = false,
                 distribution_type        = UnivariateFinite)

const AUC = AreaUnderCurve
@create_aliases AreaUnderCurve

@create_docs(AreaUnderCurve,
body=
"""
Returns the area under the ROC ([receiver operator
characteristic](https://en.wikipedia.org/wiki/Receiver_operating_characteristic))

If `missing` or `NaN` values are present, use `auc(skipinvalid(yhat, y)...)`.

$INVARIANT_LABEL
""",
scitpye = DOC_FINITE_BINARY)

# core algorithm:
function _auc(ŷ, y)
    lab_pos = classes(ŷ)[2] # 'positive' label
    scores = pdf.(ŷ, lab_pos) # associated scores
    ranks = StatsBase.tiedrank(scores)
    n = length(y)
    n_neg = 0  # to keep of the number of negative preds
    T = eltype(ranks)
    R_pos = zero(T) # sum of positive ranks
    @inbounds for (i,j) in zip(eachindex(y), eachindex(ranks))
        if y[i] == lab_pos
            R_pos += ranks[j]
        else
            n_neg += 1
        end
    end
    n_pos = n - n_neg # number of positive predictions
    U = R_pos - T(0.5)*n_pos*(n_pos + 1) # Mann-Whitney U statistic
    return U / (n_neg * n_pos)
end

# Missing values not supported, but allow `Missing` in eltype, because
# `skipinvalid(yhat, y)` does not tighten the type. See doc string above.

call(::AUC, ŷ, y) = _auc(ŷ, y)

# ========================================================
# UNAGGREGATED MEASURES

# ---------------------------------------------------------------------
# LogScore

struct LogScore{R <: Real} <: Unaggregated
    tol::R
end
LogScore(;eps=eps(), tol=eps) = LogScore(tol)

metadata_measure(LogScore;
                 instances                = ["log_score", ],
                 target_scitype           = Union{
                     Arr{<:Union{Missing,Multiclass}},
                     Arr{<:Union{Missing,OrderedFactor}},
                     Arr{<:Union{Missing,Continuous}},
                     Arr{<:Union{Missing,Count}}},
                 prediction_type          = :probabilistic,
                 orientation              = :score,
                 distribution_type        = Union{WITH_L2NORM...})

@create_aliases LogScore

@create_docs(LogScore,
body=
"""
Since the score is undefined in the case that the true observation is
predicted to occur with probability zero, probablities are clamped
between `tol` and `1-tol`, where `tol` is a constructor key-word
argument.

If `p` is the predicted probability mass or density function
corresponding to a *single* ground truth observation `η`, then the
score for that example is

    log(clamp(p(η), tol), 1 - tol)

For example, for a binary target with "yes"/"no" labels, and
predicted probability of "yes" equal to 0.8, an observation of "no"
scores `log(0.2)`.

The predictions `ŷ` should be an array of `UnivariateFinite`
distributions in the case of `Finite` target `y`, and otherwise a
supported `Distributions.UnivariateDistribution` such as `Normal` or
`Poisson`.

See also [`LogLoss`](@ref), which differs only in sign.
""",
scitype=DOC_MULTI)

# for single finite observation:
single(c::LogScore, d::UnivariateFinite, η) =
    log(clamp(pdf(d, η), c.tol, 1 - c.tol))

# for a single infinite observation:
single(c::LogScore, d::Distributions.UnivariateDistribution, η) =
    log(clamp(pdf(d, η), c.tol, 1 - c.tol))

# to resolve method ambiguities:
single(::LogScore, ::UnivariateFinite, ::Missing) = missing
single(::LogScore, ::Distributions.UnivariateDistribution, ::Missing) = missing
single(::LogScore, ::Missing, ::Missing) = missing

# performant broadasting in case of UnivariateFiniteArray:
call(c::LogScore, ŷ::UnivariateFiniteArray, y) =
    log.(clamp.(broadcast(pdf, ŷ, y), c.tol, 1 - c.tol))
call(c::LogScore, ŷ::UnivariateFiniteArray, y, w::AbstractArray) = call(c, ŷ, y) .* w

# ---------------------------------------------------------------------
# LogLoss

struct LogLoss{R <: Real} <: Unaggregated
    tol::R
end
LogLoss(;eps=eps(), tol=eps) = LogLoss(tol)

metadata_measure(LogLoss;
                 instances                = ["log_loss", "cross_entropy"],
                 target_scitype           = Union{
                     Arr{<:Union{Missing,Multiclass}},
                     Arr{<:Union{Missing,OrderedFactor}},
                     Arr{<:Union{Missing,Continuous}},
                     Arr{<:Union{Missing,Count}}},
                 prediction_type          = :probabilistic,
                 orientation              = :loss,
                 distribution_type        = Union{WITH_L2NORM...})

const CrossEntropy = LogLoss
@create_aliases LogLoss

@create_docs(LogLoss,
body=
"""
For details, see [`LogScore`](@ref), which differs only by a sign.
""",
scitype=DOC_MULTI)

# for single observation:
single(c::LogLoss, d, η) = -single(LogScore(tol=c.tol), d, η)

# to get performant broadasting in case of UnivariateFiniteArray:
call(c::LogLoss, ŷ::UnivariateFiniteArray, y) =
    -call(LogScore(tol=c.tol), ŷ, y)
call(c::LogLoss, ŷ::UnivariateFiniteArray, y, w::AbstractArray) =
    -call(LogScore(tol=c.tol), ŷ, y, w)


# -----------------------------------------------------
# BrierScore

struct BrierScore <: Unaggregated end

metadata_measure(BrierScore;
                 human_name = "Brier score (a.k.a. quadratic score)",
                 instances                = ["brier_score",],
                 target_scitype           = Union{
                     Arr{<:Union{Missing,Multiclass}},
                     Arr{<:Union{Missing,OrderedFactor}},
                     Arr{<:Union{Missing,Continuous}},
                     Arr{<:Union{Missing,Count}}},
                 prediction_type          = :probabilistic,
                 orientation              = :score,
                 distribution_type        = Union{WITH_L2NORM...})

@create_aliases BrierScore

@create_docs(BrierScore,
body=
"""
Convention as in $PROPER_SCORING_RULES

*Finite case.* If `p` is the predicted probability mass function for a
*single* observation `η`, and `C` all possible classes, then the
corresponding score for that observation is given by

``2p(η) - \\left(\\sum_{c ∈ C} p(c)^2\\right) - 1``

*Warning.* `BrierScore()` is a "score" in the sense that bigger is
better (with `0` optimal, and all other values negative). In Brier's
original 1950 paper, and many other places, it has the opposite sign,
despite the name. Moreover, the present implementation does not treat
the binary case as special, so that the score may differ in the binary
case by a factor of two from usage elsewhere.

*Infinite case.* Replacing the sum above with an integral does *not*
lead to the formula adopted here in the case of `Continuous` or
`Count` target `y`. Rather the convention in the paper cited above is
adopted, which means returning a score of

``2p(η) - ∫ p(t)^2 dt``

in the `Continuous` case (`p` the probablity density function) or

``2p(η) - ∑_t p(t)^2``

in the `Count` cae (`p` the probablity mass function).
""",
scitype=DOC_MULTI)

# calling on single finite observation:
function single(::BrierScore,
                d::UnivariateFinite,
                η)
    levels = classes(d)
    pvec = broadcast(pdf, d, levels)
    offset = 1 + sum(pvec.^2)
    return 2 * pdf(d, η) - offset
end

# calling on a single infinite observation:
single(::BrierScore, d::Distributions.UnivariateDistribution, η) =
    2*pdf(d, η) - Distributions.pdfsquaredL2norm(d)

# To get performant broadcasted version in case of UnivariateFiniteArray:
function call(
    ::BrierScore,
    ŷ::UnivariateFiniteArray,
    y
    )

    probs = pdf(ŷ, classes(first(ŷ)))
    offset = 1 .+ vec(sum(probs.^2, dims=2))

    2 .* broadcast(pdf, ŷ, y) .- offset
end
call(m::BrierScore, ŷ::UnivariateFiniteArray, y, w::AbstractArray) = call(m, ŷ, y) .* w


# -----------------------------------------------------
# BrierLoss

struct BrierLoss <: Unaggregated end

metadata_measure(BrierLoss;
                 human_name = "Brier loss (a.k.a. quadratic loss)",
                 instances                = ["brier_loss",],
                 target_scitype           = Union{
                     Arr{<:Union{Missing,Multiclass}},
                     Arr{<:Union{Missing,OrderedFactor}},
                     Arr{<:Union{Missing,Continuous}},
                     Arr{<:Union{Missing,Count}}},
                 prediction_type          = :probabilistic,
                 orientation              = :loss,
                 distribution_type        = Union{WITH_L2NORM...})

@create_aliases BrierLoss

@create_docs(BrierLoss,
body=
"""
For details, see [`BrierScore`](@ref), which differs only by a sign.
""",
scitype=DOC_MULTI)

# calling on single observation:
single(::BrierLoss, d, η) = - single(BrierScore(), d, η)

# to get performant broadcasting in case of UnivariateFiniteArray:
call(m::BrierLoss, ŷ::UnivariateFiniteArray, y) =
    -call(BrierScore(), ŷ, y)
call(m::BrierLoss, ŷ::UnivariateFiniteArray, y, w::AbstractArray) =
    -call(BrierScore(), ŷ, y, w)


# -----------------------------------------------------
# SphericalScore

struct SphericalScore{T<:Real} <: Unaggregated
    alpha::T
end
SphericalScore(; alpha=2) = SphericalScore(alpha)

metadata_measure(SphericalScore;
                 human_name               = "Spherical score",
                 instances                = ["spherical_score",],
                 target_scitype           = Union{
                     Arr{<:Union{Missing,Multiclass}},
                     Arr{<:Union{Missing,OrderedFactor}},
                     Arr{<:Union{Missing,Continuous}},
                     Arr{<:Union{Missing,Count}}},
                 prediction_type          = :probabilistic,
                 orientation              = :score,
                 distribution_type        = Union{WITH_L2NORM...})

@create_aliases SphericalScore

@create_docs(SphericalScore,
body=
"""
Convention as in $PROPER_SCORING_RULES: If `η` takes on a finite
number of classes `C` and ``p(η)` is the predicted probability for a
*single* observation `η`, then the corresponding score for that
observation is given by

``p(y)^α / \\left(\\sum_{η ∈ C} p(η)^α\\right)^{1-α} - 1``

where `α` is the measure parameter `alpha`.

$DOC_DISTRIBUTIONS

""",
scitype=DOC_MULTI)

# calling on single observations:
function single(s::SphericalScore, d::UnivariateFinite, η)
    α = s.alpha
    levels = classes(d)
    pvec = broadcast(pdf, d, levels)
    return (pdf(d, η)/norm(pvec, α))^(α - 1)
end

single(s::SphericalScore, d::Distributions.UnivariateDistribution, η) =
    pdf(d, η)/sqrt(Distributions.pdfsquaredL2norm(d))

# to compute the α-norm along last dimension:
_norm(A::AbstractArray{<:Any,N}, α) where N =
    sum(x -> x^α, A, dims=N).^(1/α)

# To get performant version in case of UnivariateFiniteArray:
function call(
    s::SphericalScore,
    ŷ::UnivariateFiniteArray,
    y
    )
    α = s.alpha
    alphanorm(A) = _norm(A, α)

    predicted_probs = pdf(ŷ, classes(first(ŷ)))

    (broadcast(pdf, ŷ, y) ./ alphanorm(predicted_probs)).^(α - 1)
end
call(s::SphericalScore, ŷ::UnivariateFiniteArray, y, w::AbstractArray) =
    call(s, ŷ, y) .* w


# ---------------------------------------------------------------------------
# Extra check for L2 norm based proper scoring rules

err_l2_norm(m) = ArgumentError(
    "Distribution not supported by $m. "*
    "Supported distributions are "*
    join(string.(map(s->"`$s`", WITH_L2NORM)), ", ", ", and "))

const ERR_UNSUPPORTED_ALPHA = ArgumentError(
    "Only `alpha = 2` is supported, unless scoring a `Finite` target. ")

# not for export:
const L2ProperScoringRules = Union{LogScore,
                                   LogLoss,
                                   BrierScore,
                                   BrierLoss,
                                   SphericalScore}

function extra_check(measure::L2ProperScoringRules, yhat, args...)

    D = nonmissing(eltype(yhat))
    D <: Distributions.Distribution || D <: UnivariateFinite ||
        (D = typeof(findfirst(x->!isinvalid(x), yhat)))
    D <: Union{Nothing, WITH_L2NORM...} ||
        throw(err_l2_norm(measure))

    if measure isa SphericalScore
        measure.alpha == 2 || throw(ERR_UNSUPPORTED_ALPHA)
    end

    return nothing
end
