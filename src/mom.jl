# TODO: include matype options in macd, rsi, and adx functions

@doc doc"""
momentum{Float64}(x::Vector{Float64}, n::Int64=1)

Momentum indicator (price now vs price `n` periods back)
""" ->
function momentum{Float64}(x::Vector{Float64}, n::Int64=1)
    @assert n>0 "Argument n must be positive."
    return diffn(x, n)
end

@doc """
roc{Float64}(x::Vector{Float64}, n::Int64=1)

Rate of change indicator (percent change between i'th observation and (i-n)'th observation)
""" ->
function roc{Float64}(x::Vector{Float64}, n::Int64=1)
    @assert n<size(x,1) && n>0 "Argument n out of bounds."
    out = zeros(x)
    @inbounds for i = n:size(x,1)
        out[i] = x[i]/x[i-n] - 1.0
    end
    out[1:n] = NaN
    return out * 100.0
end

@doc doc"""
macd{Float64}(x::Vector{Float64}, nfast::Int64=12, nslow::Int64=26, nsig::Int64=9)

Moving average convergence-divergence

`Output:`

- Column 1: MACD
- Column 2: MACD Signal Line
- Column 3: MACD Histogram
""" ->
function macd{Float64}(x::Vector{Float64}, nfast::Int64=12, nslow::Int64=26, nsig::Int64=9;
                       fastMA::Function=ema, slowMA::Function=ema, signalMA::Function=sma)
    out = zeros(Float64, (length(x),3))
    out[:,1] = fastMA(x, nfast) - slowMA(x, nslow)
    out[:,2] = signalMA(out[:,1], nsig)
    out[:,3] = out[:,1] - out[:,2]
    return out
end

@doc doc"""
rsi{Float64}(x::Vector{Float64}, n::Int64=14; ma::Function=ema, args...)

Relative strength index
""" ->
function rsi{Float64}(x::Vector{Float64}, n::Int64=14; ma::Function=ema, args...)
    @assert n<size(x,1) && n>0 "Argument n is out of bounds."
    N = size(x,1)
    ups = zeros(N)
    dns = zeros(N)
    zro = 0.0
    dx = [NaN; diff(x)]
    @inbounds for i=2:N
        if dx[i] > zro
            ups[i] = dx[i]
        elseif dx[i] < zro
            dns[i] = -dx[i]
        end
    end
    rs = [NaN; ma(ups[2:end], n; args...) ./ ma(dns[2:end], n; args...)]
    return 100.0 - 100.0 ./ (1.0 + rs)
end

@doc doc"""
adx{Float64}(hlc::Array{Float64}, n::Int64=14; wilder=true)

Average directional index

`Output:`

- Column 1: DI+
- Column 2: DI-
- Column 3: ADX
""" ->
function adx{Float64}(hlc::Array{Float64}, n::Int64=14; ma::Function=ema, args...)
    @assert n<size(hlc,1) && n>0 "Argument n is out of bounds."
    if size(hlc,2) != 3
        error("HLC array must have three columns")
    end
    N = size(hlc,1)
    updm = zeros(N)
    dndm = zeros(N)
    updm[1] = dndm[1] = NaN
    @inbounds for i = 2:N
        upmove = hlc[i,1] - hlc[i-1,1]
        dnmove = hlc[i-1,2] - hlc[i,2]
        if upmove > dnmove && upmove > 0.0
            updm[i] = upmove
        elseif dnmove > upmove && dnmove > 0.0
            dndm[i] = dnmove
        end
    end
    dip = [NaN; ma(updm[2:N], n; args...)] ./ atr(hlc, n) * 100.0
    dim = [NaN; ma(dndm[2:N], n; args...)] ./ atr(hlc, n) * 100.0
    dmx = abs(dip-dim) ./ (dip+dim)
    adx = [fill(NaN,n); ma(dmx[n+1:N], n; args...)] * 100.0
    return [dip dim adx]
end

@doc doc"""
psar{Float64}(hl::Array{Float64,2}, af::Float64=0.02, af_max::Float64=0.2, af_min::Float64=0.02)

Parabolic stop and reverse (SAR)

- hl: 2D array of high and low prices in first and second columns respectively
- af_mi: starting/initial value for acceleration factor
- af_max: maximum acceleration factor (accel factor capped at this value)
- af_inc: increment to the acceleration factor (speed of increase in accel factor)
""" ->
function psar{Float64}(hl::Array{Float64}, af_min::Float64=0.02, af_max::Float64=0.2, af_inc::Float64=af_min)
    @assert af_min<1.0 && af_min>0.0 "Argument af_min must be in [0,1]."
    @assert af_max<1.0 && af_max>0.0 "Argument af_max must be in [0,1]."
    @assert af_inc<1.0 && af_inc>0.0 "Argument af_inc must be in [0,1]."
    @assert size(hl,2) == 2 "Argument hl must have 2 columns."
    ls0 = 1
    ls = 0
    af0 = af_min
    af = 0.0
    ep0 = hl[1,1]
    ep = 0.0
    maxi = 0.0
    mini = 0.0
    sar = zeros(Float64,size(hl,1))
    sar[1] = hl[1,2] - std(hl[:,1]-hl[:,2])
    @inbounds for i = 2:size(hl,1)
        ls = ls0
        ep = ep0
        af = af0
        mini = min(hl[i-1,2], hl[i,2])
        maxi = max(hl[i-1,1], hl[i,1])
        # Long/short signals and local extrema
        if (ls == 1)
            ls0 = hl[i,2] > sar[i-1] ? 1 : -1
            ep0 = max(maxi, ep)
        else
            ls0 = hl[i,1] < sar[i-1] ? -1 : 1
            ep0 = min(mini, ep)
        end
        # Acceleration vector
        if ls0 == ls  # no signal change
            sar[i] = sar[i-1] + af*(ep-sar[i-1])
            af0 = (af == af_max) ? af_max : (af + af_inc)
            if ls0 == 1  # current long signal
                af0 = (ep0 > ep) ? af0 : af
                sar[i] = min(sar[i], mini)
            else  # current short signal
                af0 = (ep0 < ep) ? af0 : af
                sar[i] = max(sar[i], maxi)
            end
        else  # new signal
            af0 = af_min
            sar[i] = ep0
        end
    end
    return sar
end

@doc doc"""
kst{Float64}(x::Vector{Float64},
                      nroc::Vector{Int64}=[10,15,20,30], navg::Vector{Int64}=[10,10,10,15],
                      wgts::Vector{Int64}=collect(1:length(nroc)); ma::Function=sma)

KST (Know Sure Thing) -- smoothed and summed rates of change
""" ->
function kst{Float64}(x::Vector{Float64}, nroc::Vector{Int64}=[10,15,20,30], navg::Vector{Int64}=[10,10,10,15];
                      wgts::Vector{Int64}=collect(1:length(nroc)), ma::Function=sma)
    @assert length(nroc) == length(navg)
    @assert all(nroc.>0) && all(nroc.<size(x,1))
    @assert all(navg.>0) && all(navg.<size(x,1))
    N = length(x)
    k = length(nroc)
    out = zeros(x)
    @inbounds for j = 1:k
        out += ma(roc(x, nroc[j]), navg[j]) * wgts[j]
    end
    return out
end

@doc doc"""
wpr{Float64}(hlc::Array{Float64,2}, n::Int64=14)

Williams %R
""" ->
function wpr{Float64}(hlc::Array{Float64,2}, n::Int64=14)
    hihi = runmax(hlc[:,1], n, false)
    lolo = runmin(hlc[:,2], n, false)
    return -100 * (hihi - hlc[:,3]) ./ (hihi - lolo)
end

@doc doc"""
cci{Float64}(hlc::Array{Float64,2}, n::Int64=20, c::Float64=0.015; ma::Function=sma)

Commodity channel index
""" ->
function cci{Float64}(hlc::Array{Float64,2}, n::Int64=20, c::Float64=0.015; ma::Function=sma, args...)
    tp = (hlc[:,1] + hlc[:,2] + hlc[:,3]) / 3.0
    dev = runmad(tp, n, false, fun=mean)
    avg = ma(tp, n; args...)
    return (tp - avg) ./ (c * dev)
end

@doc doc"""
stoch{Float64}(hlc::Array{Float64,2}, nK::Int64=14, nD::Int64=3;
               kind::ByteString="fast", ma::Function=sma, args...)

Stochastic oscillator (fast or slow)
""" ->
function stoch{Float64}(hlc::Array{Float64,2}, nK::Int64=14, nD::Int64=3;
                        kind::Symbol=:fast, ma::Function=sma, args...)
    @assert kind == :fast || kind == :slow "Argument `kind` must be either :fast or :slow"
    @assert nK<size(hlc,1) && nK>0 "Argument `nK` out of bounds."
    @assert nD<size(hlc,1) && nD>0 "Argument `nD` out of bounds."
    hihi = runmax(hlc[:,1], nK, false)
    lolo = runmin(hlc[:,2], nK, false)
    out = zeros(Float64, (size(hlc,1),2))
    out[:,1] = (hlc[:,3]-lolo) ./ (hihi-lolo) * 100.0
    out[:,2] = ma(out[:,1], nD; args...)
    if kind == "slow"
        out[:,1] = out[:,2]
        out[:,2] = ma(out[:,1], nD; args...)
    end
    return out
end

@doc doc"""
smi{Float64}(hlc::Array{Float64,2}, n::Int64=13, nFast::Int64=2, nSlow::Int64=25, nSig::Int64=9;
             maFast::Function=ema, maSlow::Function=ema, maSig::Function=sma)

SMI (stochastic momentum oscillator)
""" ->
function smi{Float64}(hlc::Array{Float64,2}, n::Int64=13, nFast::Int64=2, nSlow::Int64=25, nSig::Int64=9;
                      maFast::Function=ema, maSlow::Function=ema, maSig::Function=sma)
    hihi = runmax(hlc[:,1], n, false)
    lolo = runmin(hlc[:,2], n, false)
    hldif = hihi-lolo
    delta = hlc[:,3] - (hihi+lolo) / 2.0
    numer = maSlow(maFast(delta, nFast), nSlow)
    denom = maSlow(maFast(hldif, nFast), nSlow) / 2.0
    out = zeros(Float64, (size(hlc,1),2))
    out[:,1] = 100.0*(numer./denom)
    out[:,2] = maSig(out[:,1])
    return out
end
