// Port of RodentFlow iOS 1.3 StatsEngine.swift (pure Foundation): special functions, distributions,
// descriptive statistics and the hypothesis tests used by the group comparison. Numerical code is
// unchanged; test names and notes are kept in English (they go into exports as is).

import Foundation

// MARK: - Special functions
//
// Everything in this file is pure Foundation so it can be unit-tested off-device.
// Numerical routines follow standard references (Numerical Recipes for the incomplete
// beta / gamma functions, R's ptukey for the studentized range distribution).

enum SpecialFunctions {
    /// ln Γ(x) using the Lanczos approximation (g = 7, n = 9).
    static func lnGamma(_ x: Double) -> Double {
        if x < 0.5 {
            return log(Double.pi / abs(sin(Double.pi * x))) - lnGamma(1 - x)
        }
        let coefficients: [Double] = [
            0.99999999999980993, 676.5203681218851, -1259.1392167224028,
            771.32342877765313, -176.61502916214059, 12.507343278686905,
            -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7
        ]
        let xx = x - 1
        var a = coefficients[0]
        let t = xx + 7.5
        for i in 1..<9 { a += coefficients[i] / (xx + Double(i)) }
        return 0.5 * log(2 * Double.pi) + (xx + 0.5) * log(t) - t + log(a)
    }

    /// Regularized incomplete beta function I_x(a, b).
    static func incompleteBeta(_ a: Double, _ b: Double, _ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let lnFront = lnGamma(a + b) - lnGamma(a) - lnGamma(b) + a * log(x) + b * log(1 - x)
        let front = exp(lnFront)
        if x < (a + 1) / (a + b + 2) {
            return front * betaContinuedFraction(a, b, x) / a
        }
        return 1 - front * betaContinuedFraction(b, a, 1 - x) / b
    }

    private static func betaContinuedFraction(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let fpmin = 1e-300
        let qab = a + b
        let qap = a + 1
        let qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < fpmin { d = fpmin }
        d = 1 / d
        var h = d
        for m in 1...400 {
            let md = Double(m)
            let m2 = 2 * md
            var aa = md * (b - md) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d
            if abs(d) < fpmin { d = fpmin }
            c = 1 + aa / c
            if abs(c) < fpmin { c = fpmin }
            d = 1 / d
            h *= d * c
            aa = -(a + md) * (qab + md) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d
            if abs(d) < fpmin { d = fpmin }
            c = 1 + aa / c
            if abs(c) < fpmin { c = fpmin }
            d = 1 / d
            let delta = d * c
            h *= delta
            if abs(delta - 1) < 3e-16 { break }
        }
        return h
    }

    /// Regularized upper incomplete gamma Q(a, x) = 1 − P(a, x).
    static func gammaQ(_ a: Double, _ x: Double) -> Double {
        if x <= 0 { return 1 }
        if x < a + 1 { return 1 - gammaPSeries(a, x) }
        return gammaQContinuedFraction(a, x)
    }

    private static func gammaPSeries(_ a: Double, _ x: Double) -> Double {
        var ap = a
        var sum = 1 / a
        var delta = sum
        for _ in 0..<2000 {
            ap += 1
            delta *= x / ap
            sum += delta
            if abs(delta) < abs(sum) * 1e-16 { break }
        }
        return sum * exp(-x + a * log(x) - lnGamma(a))
    }

    private static func gammaQContinuedFraction(_ a: Double, _ x: Double) -> Double {
        let fpmin = 1e-300
        var b = x + 1 - a
        var c = 1 / fpmin
        var d = 1 / b
        var h = d
        for i in 1...2000 {
            let an = -Double(i) * (Double(i) - a)
            b += 2
            d = an * d + b
            if abs(d) < fpmin { d = fpmin }
            c = b + an / c
            if abs(c) < fpmin { c = fpmin }
            d = 1 / d
            let delta = d * c
            h *= delta
            if abs(delta - 1) < 1e-16 { break }
        }
        return exp(-x + a * log(x) - lnGamma(a)) * h
    }

    static func normalCDF(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }
    static func normalSF(_ z: Double) -> Double { 0.5 * erfc(z / 2.0.squareRoot()) }
}

// MARK: - Distributions

enum Distributions {
    /// Two-sided p-value for a Student t statistic.
    static func tTwoSidedP(_ t: Double, df: Double) -> Double {
        if t.isInfinite { return 0 }
        guard t.isFinite, df > 0 else { return 1 }
        let x = df / (df + t * t)
        return min(1, max(0, SpecialFunctions.incompleteBeta(df / 2, 0.5, x)))
    }

    static func tCDF(_ t: Double, df: Double) -> Double {
        let p2 = tTwoSidedP(t, df: df)
        return t >= 0 ? 1 - p2 / 2 : p2 / 2
    }

    /// Quantile of the t distribution by bisection (adequate for confidence intervals).
    static func tQuantile(_ p: Double, df: Double) -> Double {
        guard p > 0, p < 1, df > 0 else { return .nan }
        var lo = -1e4
        var hi = 1e4
        for _ in 0..<200 {
            let mid = 0.5 * (lo + hi)
            if tCDF(mid, df: df) < p { lo = mid } else { hi = mid }
        }
        return 0.5 * (lo + hi)
    }

    /// Upper-tail probability of the F distribution.
    static func fSF(_ f: Double, df1: Double, df2: Double) -> Double {
        if f.isInfinite { return 0 }
        guard f.isFinite, f > 0, df1 > 0, df2 > 0 else { return 1 }
        let x = df2 / (df2 + df1 * f)
        return min(1, max(0, SpecialFunctions.incompleteBeta(df2 / 2, df1 / 2, x)))
    }

    static func chiSquareSF(_ x: Double, df: Double) -> Double {
        guard x > 0 else { return 1 }
        return min(1, max(0, SpecialFunctions.gammaQ(df / 2, x / 2)))
    }

    // Studentized range distribution — port of R's ptukey()/wprob() (Copenhaver & Holland 1988).

    private static func wprob(_ w: Double, _ rr: Double, _ cc: Double) -> Double {
        let nleg = 12, ihalf = 6
        let c1 = -30.0, c2 = -50.0, c3 = 60.0
        let bb = 8.0, wlar = 3.0, wincr1 = 2.0, wincr2 = 3.0
        let xleg: [Double] = [
            0.981560634246719250690549090149, 0.904117256370474856678465866119,
            0.769902674194304687036893833213, 0.587317954286617447296702418941,
            0.367831498998180193752691536644, 0.125233408511468915472441369464
        ]
        let aleg: [Double] = [
            0.047175336386511827194615961485, 0.106939325995318430960254718194,
            0.160078328543346226334652529543, 0.203167426723065921749064455810,
            0.233492536538354808760849898925, 0.249147045813402785000562436043
        ]
        let qsqz = w * 0.5
        if qsqz >= bb { return 1.0 }

        var prW = 2 * SpecialFunctions.normalCDF(qsqz) - 1
        if prW >= exp(c2 / cc) { prW = pow(prW, cc) } else { prW = 0 }

        let wincr = w > wlar ? wincr1 : wincr2
        var blb = qsqz
        let binc = (bb - qsqz) / wincr
        var bub = blb + binc
        var einsum = 0.0
        let cc1 = cc - 1.0
        var wi = 1.0
        while wi <= wincr {
            var elsum = 0.0
            let a = 0.5 * (bub + blb)
            let b = 0.5 * (bub - blb)
            for jj in 1...nleg {
                let j: Int
                let xx: Double
                if ihalf < jj {
                    j = (nleg - jj) + 1
                    xx = xleg[j - 1]
                } else {
                    j = jj
                    xx = -xleg[j - 1]
                }
                let c = b * xx
                let ac = a + c
                let qexpo = ac * ac
                if qexpo > c3 { break }
                let pplus = 2 * SpecialFunctions.normalCDF(ac)
                let pminus = 2 * SpecialFunctions.normalCDF(ac - w)
                var rinsum = pplus * 0.5 - pminus * 0.5
                if rinsum >= exp(c1 / cc1) {
                    rinsum = (aleg[j - 1] * exp(-(0.5 * qexpo))) * pow(rinsum, cc1)
                    elsum += rinsum
                }
            }
            elsum *= ((2.0 * b) * cc) / (2 * Double.pi).squareRoot()
            einsum += elsum
            blb = bub
            bub += binc
            wi += 1
        }
        prW += einsum
        if prW <= exp(c1 / rr) { return 0 }
        prW = pow(prW, rr)
        return min(1, prW)
    }

    /// P(Q ≤ q) for the studentized range with `k` means and `df` error degrees of freedom.
    static func studentizedRangeCDF(_ q: Double, k: Double, df: Double) -> Double {
        guard q > 0 else { return 0 }
        guard q.isFinite else { return 1 }
        guard df >= 2, k >= 2 else { return .nan }
        let rr = 1.0
        let cc = k
        if df > 25000 { return wprob(q, rr, cc) }

        let nlegq = 16, ihalfq = 8
        let eps1 = -30.0, eps2 = 1.0e-14
        let xlegq: [Double] = [
            0.989400934991649932596154173450, 0.944575023073232576077988415535,
            0.865631202387831743880467897712, 0.755404408355003033895101194847,
            0.617876244402643748446671764049, 0.458016777657227386342419442984,
            0.281603550779258913230460501460, 0.950125098376374401853193354250e-1
        ]
        let alegq: [Double] = [
            0.271524594117540948517805724560e-1, 0.622535239386478928628438369944e-1,
            0.951585116824927848099251076022e-1, 0.124628971255533872052476282192,
            0.149595988816576732081501730547, 0.169156519395002538189312079030,
            0.182603415044923588866763667969, 0.189450610455068496285396723208
        ]
        let f2 = df * 0.5
        var f2lf = ((f2 * log(df)) - (df * log(2.0))) - SpecialFunctions.lnGamma(f2)
        let f21 = f2 - 1.0
        let ff4 = df * 0.25
        let ulen: Double
        if df <= 100 { ulen = 1.0 } else if df <= 800 { ulen = 0.5 } else if df <= 5000 { ulen = 0.25 } else { ulen = 0.125 }
        f2lf += log(ulen)

        var ans = 0.0
        for i in 1...50 {
            var otsum = 0.0
            let twa1 = Double(2 * i - 1) * ulen
            for jj in 1...nlegq {
                let j: Int
                let t1: Double
                if ihalfq < jj {
                    j = jj - ihalfq - 1
                    t1 = (f2lf + (f21 * log(twa1 + (xlegq[j] * ulen)))) - (((xlegq[j] * ulen) + twa1) * ff4)
                } else {
                    j = jj - 1
                    t1 = (f2lf + (f21 * log(twa1 - (xlegq[j] * ulen)))) + (((xlegq[j] * ulen) - twa1) * ff4)
                }
                if t1 >= eps1 {
                    let qsqz: Double
                    if ihalfq < jj {
                        qsqz = q * (((xlegq[j] * ulen) + twa1) * 0.5).squareRoot()
                    } else {
                        qsqz = q * (((-(xlegq[j] * ulen)) + twa1) * 0.5).squareRoot()
                    }
                    let wprb = wprob(qsqz, rr, cc)
                    otsum += (wprb * alegq[j]) * exp(t1)
                }
            }
            if Double(i) * ulen >= 1.0 && otsum <= eps2 { break }
            ans += otsum
        }
        return min(1, max(0, ans))
    }
}

// MARK: - Descriptive statistics

struct Descriptives: Codable, Hashable {
    var n: Int
    var mean: Double
    var sd: Double
    var sem: Double
    var median: Double
    var q1: Double
    var q3: Double
    var min: Double
    var max: Double

    static let empty = Descriptives(n: 0, mean: 0, sd: 0, sem: 0, median: 0, q1: 0, q3: 0, min: 0, max: 0)
}

enum Stats {
    static func mean(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return .nan }
        return x.reduce(0, +) / Double(x.count)
    }

    /// Sample variance (n − 1 denominator).
    static func variance(_ x: [Double]) -> Double {
        guard x.count >= 2 else { return .nan }
        let m = mean(x)
        return x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
    }

    static func sd(_ x: [Double]) -> Double { variance(x).squareRoot() }

    /// Linear-interpolation quantile (R type 7 / NumPy default).
    static func quantile(_ x: [Double], _ p: Double) -> Double {
        guard !x.isEmpty else { return .nan }
        let s = x.sorted()
        if s.count == 1 { return s[0] }
        let h = Double(s.count - 1) * p
        let lo = Int(h.rounded(.down))
        let hi = Swift.min(lo + 1, s.count - 1)
        return s[lo] + (h - Double(lo)) * (s[hi] - s[lo])
    }

    static func describe(_ x: [Double]) -> Descriptives {
        let values = x.filter { $0.isFinite }
        guard !values.isEmpty else { return .empty }
        let n = values.count
        let m = mean(values)
        let s = n >= 2 ? sd(values) : 0
        return Descriptives(
            n: n,
            mean: m,
            sd: s,
            sem: n >= 2 ? s / Double(n).squareRoot() : 0,
            median: quantile(values, 0.5),
            q1: quantile(values, 0.25),
            q3: quantile(values, 0.75),
            min: values.min() ?? m,
            max: values.max() ?? m
        )
    }

    /// Average ranks (1-based) with ties sharing the mean rank, plus the tie-group sizes.
    static func ranks(_ x: [Double]) -> (ranks: [Double], tieSizes: [Int]) {
        let order = x.indices.sorted { x[$0] < x[$1] }
        var ranks = [Double](repeating: 0, count: x.count)
        var ties: [Int] = []
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count && x[order[j + 1]] == x[order[i]] { j += 1 }
            let avg = Double(i + j + 2) / 2.0
            for k in i...j { ranks[order[k]] = avg }
            if j > i { ties.append(j - i + 1) }
            i = j + 1
        }
        return (ranks, ties)
    }

    /// True when a spread (SD / SE) is zero up to floating-point noise relative to the data scale.
    /// Tests are reported as not computable in that case instead of producing absurd statistics.
    static func negligible(_ spread: Double, scale values: [Double]) -> Bool {
        let scale = values.map { abs($0) }.max() ?? 0
        return !(spread > 1e-9 * Swift.max(scale, 1e-300))
    }

    /// Holm–Bonferroni step-down adjustment.
    static func holm(_ p: [Double]) -> [Double] {
        let m = p.count
        guard m > 0 else { return [] }
        let order = p.indices.sorted { p[$0] < p[$1] }
        var adjusted = [Double](repeating: 1, count: m)
        var running = 0.0
        for (rank, index) in order.enumerated() {
            let value = Swift.min(1, Double(m - rank) * p[index])
            running = Swift.max(running, value)
            adjusted[index] = running
        }
        return adjusted
    }
}

// MARK: - Test results

struct TestResult: Codable, Hashable {
    var name: String
    var statisticName: String
    var statistic: Double
    var df1: Double?
    var df2: Double?
    var p: Double
    var effectName: String?
    var effect: Double?
    var note: String?

    /// APA-like one-line report, e.g. "t(11.4) = 2.31, p = 0.041".
    var reportLine: String {
        var df = ""
        if let df1, let df2 {
            df = "(\(StatsFormat.df(df1)), \(StatsFormat.df(df2)))"
        } else if let df1 {
            df = "(\(StatsFormat.df(df1)))"
        }
        var line = "\(statisticName)\(df) = \(StatsFormat.number(statistic)), \(StatsFormat.p(p))"
        if let effectName, let effect { line += ", \(effectName) = \(StatsFormat.number(effect))" }
        return line
    }
}

struct PairwiseComparison: Codable, Hashable, Identifiable {
    var id: String { "\(groupA)|\(groupB)|\(level ?? "")" }
    var groupA: String
    var groupB: String
    var level: String?
    /// Mean (or median for rank tests) of A minus B.
    var difference: Double
    var statisticName: String
    var statistic: Double
    var p: Double
    var pAdjusted: Double
    var method: String
}

enum StatsFormat {
    static func p(_ p: Double) -> String {
        guard p.isFinite else { return "p = n/a" }
        if p < 0.0001 { return "p < 0.0001" }
        if p < 0.001 { return String(format: "p = %.4f", p) }
        return String(format: "p = %.3f", p)
    }

    static func stars(_ p: Double) -> String {
        guard p.isFinite else { return "" }
        if p < 0.0001 { return "****" }
        if p < 0.001 { return "***" }
        if p < 0.01 { return "**" }
        if p < 0.05 { return "*" }
        return "ns"
    }

    static func number(_ x: Double) -> String {
        guard x.isFinite else { return "n/a" }
        let a = abs(x)
        if a == 0 { return "0" }
        if a >= 1000 { return String(format: "%.0f", x) }
        if a >= 100 { return String(format: "%.1f", x) }
        if a >= 1 { return String(format: "%.2f", x) }
        if a >= 0.01 { return String(format: "%.3f", x) }
        return String(format: "%.2e", x)
    }

    static func df(_ x: Double) -> String {
        abs(x - x.rounded()) < 1e-9 ? String(format: "%.0f", x) : String(format: "%.2f", x)
    }
}

// MARK: - Hypothesis tests

enum StatTests {
    // Two independent samples ------------------------------------------------------------

    static func welchT(_ a: [Double], _ b: [Double]) -> TestResult? {
        guard a.count >= 2, b.count >= 2 else { return nil }
        let na = Double(a.count), nb = Double(b.count)
        let ma = Stats.mean(a), mb = Stats.mean(b)
        let va = Stats.variance(a), vb = Stats.variance(b)
        let sa = va / na, sb = vb / nb
        let se = (sa + sb).squareRoot()
        let g = hedgesG(a, b)
        if Stats.negligible(se, scale: a + b) { return nil }
        let t = (ma - mb) / se
        let df = (sa + sb) * (sa + sb) / (sa * sa / (na - 1) + sb * sb / (nb - 1))
        return TestResult(name: "Welch's t-test", statisticName: "t", statistic: t, df1: df,
                          p: Distributions.tTwoSidedP(t, df: df), effectName: "Hedges' g", effect: g)
    }

    static func studentT(_ a: [Double], _ b: [Double]) -> TestResult? {
        guard a.count >= 2, b.count >= 2 else { return nil }
        let na = Double(a.count), nb = Double(b.count)
        let df = na + nb - 2
        let pooled = ((na - 1) * Stats.variance(a) + (nb - 1) * Stats.variance(b)) / df
        let se = (pooled * (1 / na + 1 / nb)).squareRoot()
        let diff = Stats.mean(a) - Stats.mean(b)
        if Stats.negligible(se, scale: a + b) { return nil }
        let t = diff / se
        return TestResult(name: "Unpaired t-test", statisticName: "t", statistic: t, df1: df,
                          p: Distributions.tTwoSidedP(t, df: df), effectName: "Hedges' g", effect: hedgesG(a, b))
    }

    static func hedgesG(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count >= 2, b.count >= 2 else { return nil }
        let na = Double(a.count), nb = Double(b.count)
        let pooled = (((na - 1) * Stats.variance(a) + (nb - 1) * Stats.variance(b)) / (na + nb - 2)).squareRoot()
        if Stats.negligible(pooled, scale: a + b) { return nil }
        let d = (Stats.mean(a) - Stats.mean(b)) / pooled
        return d * (1 - 3 / (4 * (na + nb) - 9))
    }

    /// 95% CI of the mean difference (a − b) using the Welch standard error.
    static func welchDifferenceCI(_ a: [Double], _ b: [Double], level: Double = 0.95) -> (low: Double, high: Double)? {
        guard a.count >= 2, b.count >= 2 else { return nil }
        let na = Double(a.count), nb = Double(b.count)
        let sa = Stats.variance(a) / na, sb = Stats.variance(b) / nb
        let se = (sa + sb).squareRoot()
        if Stats.negligible(se, scale: a + b) { return nil }
        let df = (sa + sb) * (sa + sb) / (sa * sa / (na - 1) + sb * sb / (nb - 1))
        let tq = Distributions.tQuantile(1 - (1 - level) / 2, df: df)
        let diff = Stats.mean(a) - Stats.mean(b)
        return (diff - tq * se, diff + tq * se)
    }

    /// Mann–Whitney U. Exact null distribution when there are no ties and samples are small,
    /// otherwise the normal approximation with tie and continuity corrections (as in SciPy).
    static func mannWhitney(_ a: [Double], _ b: [Double]) -> TestResult? {
        guard !a.isEmpty, !b.isEmpty, a.count + b.count >= 3 else { return nil }
        let n1 = a.count, n2 = b.count
        let (r, ties) = Stats.ranks(a + b)
        let r1 = r[0..<n1].reduce(0, +)
        let u1 = r1 - Double(n1 * (n1 + 1)) / 2
        let u2 = Double(n1 * n2) - u1
        let uMax = max(u1, u2)
        let p: Double
        let method: String
        if ties.isEmpty && n1 <= 20 && n2 <= 20 {
            p = min(1, 2 * exactUUpperTail(Int(uMax.rounded()), n1, n2))
            method = "exact"
        } else {
            let n = Double(n1 + n2)
            let tieTerm = ties.reduce(0.0) { $0 + Double($1 * $1 * $1 - $1) }
            let sigma = (Double(n1 * n2) / 12 * ((n + 1) - tieTerm / (n * (n - 1)))).squareRoot()
            if sigma == 0 {
                p = 1
            } else {
                let z = (uMax - Double(n1 * n2) / 2 - 0.5) / sigma
                p = min(1, 2 * SpecialFunctions.normalSF(z))
            }
            method = "normal approximation"
        }
        let rankBiserial = 2 * u1 / Double(n1 * n2) - 1
        return TestResult(name: "Mann–Whitney U test", statisticName: "U", statistic: u1, p: p,
                          effectName: "rank-biserial r", effect: rankBiserial, note: method)
    }

    /// P(U ≥ u) under H0 for sample sizes n1, n2 (no ties).
    private static func exactUUpperTail(_ u: Int, _ n1: Int, _ n2: Int) -> Double {
        let maxU = n1 * n2
        // counts[i][j] = distribution of U for sizes (i, j); built iteratively.
        var previousRow = [[Double]](repeating: [1], count: n2 + 1) // i = 0: U = 0 only
        for i in 1...n1 {
            var row = [[Double]](repeating: [], count: n2 + 1)
            row[0] = [1] // j = 0: U = 0 only
            for j in 1...n2 {
                let size = i * j + 1
                var dist = [Double](repeating: 0, count: size)
                // f(i, j, u) = f(i − 1, j, u − j) + f(i, j − 1, u)
                let left = previousRow[j]
                for (k, value) in left.enumerated() where k + j < size { dist[k + j] += value }
                let down = row[j - 1]
                for (k, value) in down.enumerated() where k < size { dist[k] += value }
                row[j] = dist
            }
            previousRow = row
        }
        let dist = previousRow[n2]
        let total = dist.reduce(0, +)
        guard total > 0, u <= maxU else { return 0 }
        let upper = dist[max(0, u)...].reduce(0, +)
        return upper / total
    }

    // Paired / one-sample ----------------------------------------------------------------

    static func pairedT(_ a: [Double], _ b: [Double]) -> TestResult? {
        guard a.count == b.count else { return nil }
        let d = zip(a, b).map { $0 - $1 }
        guard var result = oneSampleT(d, mu: 0) else { return nil }
        result.name = "Paired t-test"
        result.effectName = "Cohen's dz"
        return result
    }

    static func oneSampleT(_ x: [Double], mu: Double) -> TestResult? {
        guard x.count >= 2 else { return nil }
        let n = Double(x.count)
        let m = Stats.mean(x)
        let s = Stats.sd(x)
        let df = n - 1
        if Stats.negligible(s, scale: x + [mu]) { return nil }
        let t = (m - mu) / (s / n.squareRoot())
        return TestResult(name: "One-sample t-test", statisticName: "t", statistic: t, df1: df,
                          p: Distributions.tTwoSidedP(t, df: df), effectName: "Cohen's d", effect: (m - mu) / s)
    }

    /// Wilcoxon signed-rank test on differences `d` (zeros discarded, Wilcoxon's method).
    static func wilcoxonSignedRank(_ differences: [Double]) -> TestResult? {
        let d = differences.filter { $0 != 0 && $0.isFinite }
        let n = d.count
        guard n >= 1 else {
            return TestResult(name: "Wilcoxon signed-rank test", statisticName: "W", statistic: 0, p: 1,
                              note: "All differences are zero.")
        }
        let (r, ties) = Stats.ranks(d.map { abs($0) })
        var wPlus = 0.0
        var wMinus = 0.0
        for (i, value) in d.enumerated() {
            if value > 0 { wPlus += r[i] } else { wMinus += r[i] }
        }
        let w = min(wPlus, wMinus)
        let p: Double
        let method: String
        if ties.isEmpty && n <= 30 {
            // Exact: distribution of the signed-rank sum over 2^n sign patterns.
            let maxSum = n * (n + 1) / 2
            var counts = [Double](repeating: 0, count: maxSum + 1)
            counts[0] = 1
            for k in 1...n {
                var s = maxSum
                while s >= k {
                    counts[s] += counts[s - k]
                    s -= 1
                }
            }
            let total = pow(2.0, Double(n))
            let wi = Int(w.rounded())
            let lower = counts[0...min(maxSum, wi)].reduce(0, +)
            p = min(1, 2 * lower / total)
            method = "exact"
        } else {
            let nn = Double(n)
            let meanW = nn * (nn + 1) / 4
            let tieTerm = ties.reduce(0.0) { $0 + Double($1 * $1 * $1 - $1) }
            let variance = nn * (nn + 1) * (2 * nn + 1) / 24 - tieTerm / 48
            if variance <= 0 {
                p = 1
            } else {
                let z = (w - meanW) / variance.squareRoot()
                p = min(1, 2 * SpecialFunctions.normalCDF(-abs(z)))
            }
            method = "normal approximation"
        }
        let rbc = (wPlus - wMinus) / (wPlus + wMinus)
        return TestResult(name: "Wilcoxon signed-rank test", statisticName: "W", statistic: w, p: p,
                          effectName: "matched-pairs r", effect: rbc, note: method)
    }

    // k independent groups ----------------------------------------------------------------

    struct ANOVAOutput {
        var test: TestResult
        var msError: Double
        var dfError: Double
    }

    static func oneWayANOVA(_ groups: [[Double]]) -> ANOVAOutput? {
        let valid = groups.filter { !$0.isEmpty }
        guard valid.count >= 2 else { return nil }
        let all = valid.flatMap { $0 }
        let n = Double(all.count)
        let k = Double(valid.count)
        guard n > k else { return nil }
        let grand = Stats.mean(all)
        var ssb = 0.0
        var ssw = 0.0
        for g in valid {
            let m = Stats.mean(g)
            ssb += Double(g.count) * (m - grand) * (m - grand)
            ssw += g.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        }
        let dfb = k - 1
        let dfw = n - k
        let msw = ssw / dfw
        if Stats.negligible(msw.squareRoot(), scale: all) { return nil }
        let f = (ssb / dfb) / msw
        let p = Distributions.fSF(f, df1: dfb, df2: dfw)
        let eta = ssb + ssw > 0 ? ssb / (ssb + ssw) : 0
        let test = TestResult(name: "One-way ANOVA", statisticName: "F", statistic: f, df1: dfb, df2: dfw, p: p,
                              effectName: "η²", effect: eta)
        return ANOVAOutput(test: test, msError: msw, dfError: dfw)
    }

    /// Tukey–Kramer HSD for all pairs (or only pairs that include `controlIndex`).
    static func tukeyHSD(_ groups: [[Double]], names: [String], controlIndex: Int? = nil) -> [PairwiseComparison] {
        guard let anova = oneWayANOVA(groups), anova.msError > 0 else { return [] }
        let k = Double(groups.filter { !$0.isEmpty }.count)
        var output: [PairwiseComparison] = []
        for i in 0..<groups.count {
            for j in (i + 1)..<groups.count {
                if let c = controlIndex, i != c && j != c { continue }
                guard !groups[i].isEmpty, !groups[j].isEmpty else { continue }
                let diff = Stats.mean(groups[i]) - Stats.mean(groups[j])
                let se = (anova.msError / 2 * (1 / Double(groups[i].count) + 1 / Double(groups[j].count))).squareRoot()
                let q = abs(diff) / se
                let p = 1 - Distributions.studentizedRangeCDF(q, k: k, df: anova.dfError)
                output.append(PairwiseComparison(
                    groupA: names[i], groupB: names[j], level: nil, difference: diff,
                    statisticName: "q", statistic: q, p: max(0, p), pAdjusted: min(1, max(0, p)),
                    method: "Tukey–Kramer HSD"
                ))
            }
        }
        return output
    }

    static func kruskalWallis(_ groups: [[Double]]) -> TestResult? {
        let valid = groups.filter { !$0.isEmpty }
        guard valid.count >= 2 else { return nil }
        let all = valid.flatMap { $0 }
        let n = Double(all.count)
        guard n >= 3 else { return nil }
        let (r, ties) = Stats.ranks(all)
        var h = 0.0
        var offset = 0
        for g in valid {
            let rs = r[offset..<(offset + g.count)].reduce(0, +)
            h += rs * rs / Double(g.count)
            offset += g.count
        }
        h = 12 / (n * (n + 1)) * h - 3 * (n + 1)
        let tieTerm = ties.reduce(0.0) { $0 + Double($1 * $1 * $1 - $1) }
        let correction = 1 - tieTerm / (n * n * n - n)
        if correction > 0 { h /= correction }
        let k = Double(valid.count)
        let eta = max(0, (h - k + 1) / (n - k))
        return TestResult(name: "Kruskal–Wallis test", statisticName: "H", statistic: h, df1: k - 1,
                          p: Distributions.chiSquareSF(h, df: k - 1), effectName: "η²(H)", effect: eta)
    }

    /// Dunn's post-hoc test with Holm adjustment.
    static func dunn(_ groups: [[Double]], names: [String], controlIndex: Int? = nil) -> [PairwiseComparison] {
        let all = groups.flatMap { $0 }
        let n = Double(all.count)
        guard n >= 3 else { return [] }
        let (r, ties) = Stats.ranks(all)
        var meanRanks: [Double] = []
        var offset = 0
        for g in groups {
            meanRanks.append(g.isEmpty ? .nan : r[offset..<(offset + g.count)].reduce(0, +) / Double(g.count))
            offset += g.count
        }
        let tieTerm = ties.reduce(0.0) { $0 + Double($1 * $1 * $1 - $1) }
        let base = n * (n + 1) / 12 - tieTerm / (12 * (n - 1))
        var raw: [PairwiseComparison] = []
        for i in 0..<groups.count {
            for j in (i + 1)..<groups.count {
                if let c = controlIndex, i != c && j != c { continue }
                guard !groups[i].isEmpty, !groups[j].isEmpty else { continue }
                let se = (base * (1 / Double(groups[i].count) + 1 / Double(groups[j].count))).squareRoot()
                let z = se > 0 ? (meanRanks[i] - meanRanks[j]) / se : 0
                let p = min(1, 2 * SpecialFunctions.normalSF(abs(z)))
                raw.append(PairwiseComparison(
                    groupA: names[i], groupB: names[j], level: nil,
                    difference: Stats.quantile(groups[i], 0.5) - Stats.quantile(groups[j], 0.5),
                    statisticName: "z", statistic: z, p: p, pAdjusted: p, method: "Dunn's test (Holm)"
                ))
            }
        }
        let adjusted = Stats.holm(raw.map(\.p))
        for i in raw.indices { raw[i].pAdjusted = adjusted[i] }
        return raw
    }

    // Repeated measures ------------------------------------------------------------------

    struct MixedANOVAOutput: Codable, Hashable {
        var group: TestResult?
        var level: TestResult
        var interaction: TestResult?
        var epsilonGG: Double
        var subjectsUsed: Int
        var subjectsDropped: Int
    }

    /// Split-plot (mixed) ANOVA: between factor = group, within factor = level (day/trial/bin).
    /// `data[g]` is a list of subjects in group g; every subject must have one value per level.
    /// With a single group this reduces to a one-way repeated-measures ANOVA.
    static func mixedANOVA(_ data: [[[Double]]], levelCount b: Int, dropped: Int = 0) -> MixedANOVAOutput? {
        let groups = data.filter { !$0.isEmpty }
        let a = groups.count
        guard a >= 1, b >= 2 else { return nil }
        let subjects = groups.flatMap { $0 }
        guard subjects.allSatisfy({ $0.count == b }) else { return nil }
        let nTotal = subjects.count
        guard nTotal - a >= 1 else { return nil }
        let bD = Double(b)
        let all = subjects.flatMap { $0 }
        let grand = Stats.mean(all)

        var ssTotal = 0.0
        for v in all { ssTotal += (v - grand) * (v - grand) }

        var ssSubjects = 0.0
        for s in subjects {
            let m = Stats.mean(s)
            ssSubjects += bD * (m - grand) * (m - grand)
        }

        var ssGroup = 0.0
        var ssCells = 0.0
        for g in groups {
            let gm = Stats.mean(g.flatMap { $0 })
            ssGroup += Double(g.count) * bD * (gm - grand) * (gm - grand)
            for j in 0..<b {
                let cm = Stats.mean(g.map { $0[j] })
                ssCells += Double(g.count) * (cm - grand) * (cm - grand)
            }
        }

        var ssLevel = 0.0
        for j in 0..<b {
            let lm = Stats.mean(subjects.map { $0[j] })
            ssLevel += Double(nTotal) * (lm - grand) * (lm - grand)
        }

        let ssSubjWithin = ssSubjects - ssGroup
        let ssWithin = ssTotal - ssSubjects
        let ssInteraction = a >= 2 ? ssCells - ssGroup - ssLevel : 0
        let ssError = ssWithin - ssLevel - ssInteraction

        let dfGroup = Double(a - 1)
        let dfSubjWithin = Double(nTotal - a)
        let dfLevel = bD - 1
        let dfInteraction = Double(a - 1) * (bD - 1)
        let dfError = Double(nTotal - a) * (bD - 1)

        // Greenhouse–Geisser epsilon from the pooled within-group covariance matrix.
        var cov = [[Double]](repeating: [Double](repeating: 0, count: b), count: b)
        for g in groups {
            let means = (0..<b).map { j in Stats.mean(g.map { $0[j] }) }
            for s in g {
                for i in 0..<b {
                    for j in 0..<b { cov[i][j] += (s[i] - means[i]) * (s[j] - means[j]) }
                }
            }
        }
        for i in 0..<b { for j in 0..<b { cov[i][j] /= dfSubjWithin } }
        let rowMeans = cov.map { Stats.mean($0) }
        let grandCov = Stats.mean(rowMeans)
        var trace = 0.0
        var sumSquares = 0.0
        for i in 0..<b {
            for j in 0..<b {
                let centered = cov[i][j] - rowMeans[i] - rowMeans[j] + grandCov
                if i == j { trace += centered }
                sumSquares += centered * centered
            }
        }
        var epsilon = sumSquares > 0 ? (trace * trace) / ((bD - 1) * sumSquares) : 1
        epsilon = min(1, max(1 / (bD - 1), epsilon))

        // Zero residual variance (identical values) makes the F tests undefined.
        if Stats.negligible((max(0, ssError) / dfError).squareRoot(), scale: all) { return nil }

        func fTest(_ name: String, ss: Double, df: Double, ssErr: Double, dfErr: Double, corrected: Bool) -> TestResult {
            let msErr = max(ssErr / dfErr, 1e-300)
            let f = (ss / df) / msErr
            let e = corrected ? epsilon : 1
            let p = Distributions.fSF(f, df1: df * e, df2: dfErr * e)
            let partialEta = ss + ssErr > 0 ? ss / (ss + ssErr) : 0
            return TestResult(name: name, statisticName: "F", statistic: f, df1: df * e, df2: dfErr * e, p: p,
                              effectName: "partial η²", effect: partialEta,
                              note: corrected && b > 2 ? String(format: "Greenhouse–Geisser ε = %.3f", epsilon) : nil)
        }

        let levelTest = fTest("Within (level)", ss: ssLevel, df: dfLevel, ssErr: ssError, dfErr: dfError, corrected: b > 2)
        var groupTest: TestResult?
        var interactionTest: TestResult?
        if a >= 2 && dfSubjWithin > 0 {
            groupTest = fTest("Between (group)", ss: ssGroup, df: dfGroup, ssErr: ssSubjWithin, dfErr: dfSubjWithin, corrected: false)
            interactionTest = fTest("Group × level", ss: ssInteraction, df: dfInteraction, ssErr: ssError, dfErr: dfError, corrected: b > 2)
        }
        return MixedANOVAOutput(group: groupTest, level: levelTest, interaction: interactionTest,
                                epsilonGG: epsilon, subjectsUsed: nTotal, subjectsDropped: dropped)
    }

    /// Friedman test (non-parametric one-way repeated measures). `rows` = subjects × levels.
    static func friedman(_ rows: [[Double]]) -> TestResult? {
        guard let k = rows.first?.count, k >= 2, rows.count >= 2, rows.allSatisfy({ $0.count == k }) else { return nil }
        let n = Double(rows.count)
        let kd = Double(k)
        var rankSums = [Double](repeating: 0, count: k)
        var tieSum = 0.0
        for row in rows {
            let (r, ties) = Stats.ranks(row)
            for j in 0..<k { rankSums[j] += r[j] }
            tieSum += ties.reduce(0.0) { $0 + Double($1 * $1 * $1 - $1) }
        }
        let ss = rankSums.reduce(0) { $0 + $1 * $1 }
        var chi = 12 / (n * kd * (kd + 1)) * ss - 3 * n * (kd + 1)
        let correction = 1 - tieSum / (n * (kd * kd * kd - kd))
        if correction > 0 { chi /= correction }
        let w = chi / (n * (kd - 1))
        return TestResult(name: "Friedman test", statisticName: "χ²", statistic: chi, df1: kd - 1,
                          p: Distributions.chiSquareSF(chi, df: kd - 1), effectName: "Kendall's W", effect: w)
    }
}
