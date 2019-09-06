# Users of this module should first read the document
# https://alan-turing-institute.github.io/MLJ.jl/dev/adding_models_for_general_use/

module MLJBase

export MLJType, Model, Supervised, Unsupervised
export Deterministic, Probabilistic, Interval
export DeterministicNetwork, ProbabilisticNetwork, UnsupervisedNetwork
export fit, update, clean!
export predict, predict_mean, predict_mode, fitted_params
export transform, inverse_transform, se, evaluate, best
export load_path, package_url, package_name, package_uuid
export input_scitype, supports_weights
export target_scitype, output_scitype
export is_pure_julia, is_wrapper, prediction_type                              

export params                                        # parameters.jl
export reconstruct, int, decoder, classes            # data.jl
export selectrows, selectcols, select, nrows         # data.jl
export table, levels_seen, matrix, container_type    # data.jl
export partition, unpack                             # data.jl
export @set_defaults                                 # utilities.jl
export HANDLE_GIVEN_ID, @more, @constant             # show.jl
export color_on, color_off                           # show.jl
export UnivariateFinite, average                     # distributions.jl
export SupervisedTask, UnsupervisedTask, MLJTask     # tasks.jl
export X_and_y, X_, y_, nrows, nfeatures             # tasks.jl
export info                                          # info.jl
export @load_boston, @load_ames, @load_iris          # datasets.jl
export @load_reduced_ames                            # datasets.jl
export @load_crabs                                   # datasets.jl


# methods from other packages to be rexported:
export pdf, mean, mode

# re-export of ScientificTypes (`Table` not exported):
export trait
export Scientific, Found, Unknown, Finite, Infinite
export OrderedFactor, Multiclass, Count, Continuous
export Binary, ColorImage, GrayImage, Image
export scitype, scitype_union, coerce, schema

import Base.==

using Tables
using OrderedCollections # already a dependency of StatsBase
import Distributions
import Distributions: pdf, mode
using CategoricalArrays
using OrderedCollections
import CategoricalArrays
using ScientificTypes
import ScientificTypes: trait

# to be extended:
import StatsBase: fit, predict, fit!

# from Standard Library:
using Statistics
using Random
using InteractiveUtils
using SparseArrays


## CONSTANTS

# the directory containing this file:
const srcdir = dirname(@__FILE__)
# horizontal space for field names in `MLJType` object display:
const COLUMN_WIDTH = 24
# how deep to display fields of `MLJType` objects:
const DEFAULT_SHOW_DEPTH = 0

include("utilities.jl")


## BASE TYPES 

abstract type MLJType end
include("equality.jl") # equality for MLJType objects


## ABSTRACT MODEL TYPES

# for storing hyperparameters:
abstract type Model <: MLJType end

abstract type Supervised <: Model end
abstract type Unsupervised <: Model end

# supervised models that `predict` probability distributions are of:
abstract type Probabilistic <: Supervised end

# supervised models that `predict` point-values are of:
abstract type Deterministic <: Supervised end

# supervised models that `predict` intervals:
abstract type Interval <: Supervised end

# for models that are "exported" learning networks (return a Node as
# their fit-result; see MLJ docs:
abstract type ProbabilisticNetwork <: Probabilistic end
abstract type DeterministicNetwork <: Deterministic end
abstract type UnsupervisedNetwork <: Unsupervised end


## THE MODEL INTERFACE

# every model interface must implement a `fit` method of the form
# `fit(model, verbosity::Integer, training_args...) -> fitresult, cache, report` 
# or, one the simplified versions
# `fit(model, training_args...) -> fitresult`
# `fit(model, X, ys...) -> fitresult`
fit(model::Model, verbosity::Integer, args...) = fit(model, args...), nothing, nothing

# each model interface may optionally overload the following refitting
# method:
update(model::Model, verbosity, fitresult, cache, args...) =
    fit(model, verbosity, args...)

# methods dispatched on a model and fit-result are called
# *operations*.  supervised models must implement a `predict`
# operation (extending the `predict` method of StatsBase).

# unsupervised methods must implement this operation:
function transform end

# unsupervised methods may implement this operation:
function inverse_transform end

# this operation can be optionally overloaded to provide access to
# fitted parameters (eg, coeficients of linear model):
fitted_params(::Model, fitresult) = (fitresult=fitresult,)

# operations implemented by some meta-models:
function se end
function evaluate end
function best end

# a model wishing invalid hyperparameters to be corrected with a
# warning should overload this method (return value is the warning
# message):
clean!(model::Model) = ""

# model trait names:
const ALL_TRAITS = [:input_scitype, :output_scitype, :target_scitype,
                    :is_pure_julia, :package_name, :package_license,
                    :load_path, :package_uuid,
                    :package_url, :is_wrapper, :supports_weights, :docstring,
                    :name, :is_supervised, :prediction_type]
const SUPERVISED_TRAITS = filter(ALL_TRAITS) do trait
    !(trait in [:output_scitype,])
end
const UNSUPERVISED_TRAITS = filter(ALL_TRAITS) do trait
    !(trait in [:target_scitype, :prediction_type, :supports_weights])
end

# fallback trait declarations:
input_scitype(::Type) = Unknown
output_scitype(::Type) = Unknown
target_scitype(::Type) = Unknown  # used for measures too
is_pure_julia(::Type) = missing
package_name(::Type) = "unknown"
package_license(::Type) = "unknown"
load_path(::Type) = "unknown"
package_uuid(::Type) = "unknown"
package_url(::Type) = "unknown"
is_wrapper(::Type) = false
supports_weights(::Type) = false  # used for measures too
docstring(object::Type{<:MLJType}) =
    "$(name(object)) from $(package_name(object)).jl.\n"*
"[Documentation]($(package_url(object)))."

# "derived" traits:
name(M::Type{<:MLJType}) = split(string(coretype(M)), '.')[end] |> String
is_supervised(::Type{<:Type}) = false
is_supervised(::Type{<:Supervised}) = true
prediction_type(::Type) = :unknown # used for measures too
prediction_type(::Type{<:Deterministic}) = :deterministic
prediction_type(::Type{<:Probabilistic}) = :probabilistic
prediction_type(::Type{<:Interval}) = :interval

# declare `trait(object) = trait(typeof(object))`:      
for trait in ALL_TRAITS
    eval(quote
        $trait(object) = $trait(typeof(object))
    end)
end

# probabilistic supervised models may also overload one or more of
# `predict_mode`, `predict_median` and `predict_mean` defined below.

# mode:
predict_mode(model::Probabilistic, fitresult, Xnew) =
    mode.(predict(model, fitresult, Xnew))

# mean:
predict_mean(model::Probabilistic, fitresult, Xnew) =
    mean.(predict(model, fitresult, Xnew))

# median:
predict_median(model::Probabilistic, fitresult, Xnew) =
    median.(predict(model, fitresult, Xnew))

# for unpacking the fields of MLJ objects:
include("parameters.jl")

# for displaying objects of `MLJType`:
include("show.jl")

# convenience methods for manipulating categorical and tabular data
include("data.jl")

# probability distributions and methods not provided by
# Distributions.jl package:
include("distributions.jl")

include("info.jl")
include("datasets.jl") # importing CSV will also load datasets_requires.jl
include("tasks.jl")

# __init__() function:
include("init.jl")

end # module
