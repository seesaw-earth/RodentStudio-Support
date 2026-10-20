import Foundation
struct FlowResultSeries: Codable, Hashable, Identifiable {
    let key:String;let name:String;let unit:String;let xLabel:String
    let x:[Double];let y:[Double]
    var id:String{key}
}
struct FlowAssayComputation: Codable, Hashable {
    var metrics:[String:Double]=[:]
    var series:[FlowResultSeries]=[]
    var labels:[String:String]=[:]
    var parameters:[String:String]=[:]
    var qcFlags:[String]=[]
    mutating func set(_ key:String,_ value:Double?) {
        if let value,value.isFinite {metrics[key]=value}
    }
    mutating func param(_ key:String,_ value:Double,decimals:Int=2) {
        parameters[key]=String(format:"%.\(decimals)f",value)
    }
    mutating func addSeries(_ key:String,_ name:String,unit:String,xLabel:String,x:[Double],y:[Double]) {
        let pairs=zip(x,y).filter{$0.0.isFinite && $0.1.isFinite}
        if pairs.isEmpty{return}
        series.append(FlowResultSeries(key:key,name:name,unit:unit,xLabel:xLabel,
                              x:pairs.map{$0.0},y:pairs.map{$0.1}))
    }
}
enum FlowStats {
    static func mean(_ x:[Double])->Double {x.isEmpty ? .nan : x.reduce(0,+)/Double(x.count)}
    static func quantile(_ x:[Double],_ p:Double)->Double {
        guard !x.isEmpty else{return .nan}
        let s=x.sorted();if s.count==1{return s[0]}
        let h=Double(s.count-1)*p,lo=Int(h.rounded(.down)),hi=min(lo+1,s.count-1)
        return s[lo]+(h-Double(lo))*(s[hi]-s[lo])
    }
}
