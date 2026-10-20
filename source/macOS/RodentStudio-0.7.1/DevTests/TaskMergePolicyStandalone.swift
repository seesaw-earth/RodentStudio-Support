import Foundation
struct StudyAssay: Equatable { let rawValue: String }
struct GroupStyle: Equatable { let order: Int }
struct NativeExperiment {
 var id: UUID = UUID(); var name: String; var assay: StudyAssay; var groupStyles: [String:GroupStyle]?; var notes: String?
 var hasNotes: Bool { !(notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
struct VideoRecord {
 var id: UUID = UUID(); var experimentID: UUID?; var animalKey: String; var groupKey: String; var sessionNumber: Int?; var sex: String?; var runFolder: String?
}
struct NativeProject { var experiments: [NativeExperiment]; var videos: [VideoRecord] }
struct WorkspaceDocument { var projects: [NativeProject] }
func task(_ name: String, _ kind: String = "openfield", _ notes: String? = nil, groups: [String:GroupStyle]? = nil) -> NativeExperiment {
 NativeExperiment(name: name, assay: StudyAssay(rawValue: kind), groupStyles: groups, notes: notes)
}
func video(_ t: NativeExperiment, _ animal: String = "M1", _ nr: Int? = 1, _ group: String = "ctrl", _ sex: String? = "F") -> VideoRecord {
 VideoRecord(experimentID: t.id, animalKey: animal, groupKey: group, sessionNumber: nr, sex: sex, runFolder: "stable-run")
}
func check(_ bool: @autoclosure () -> Bool, _ msg: String) { if !bool() { fatalError(msg) } }
@main struct TestSuite {
 static func main() {
  let a = task(" Open Field ",groups:["ctrl":GroupStyle(order:0)])
  let b = task("open field",groups:["drug":GroupStyle(order:1)])
  let c = task("Open Field", "openfield", "protocol A")
  let d = task("Open Field", "another-assay", "protocol A")
  let e = task("Open Field", "openfield", "protocol A")
  let f = task("open field", "openfield", "protocol B")
  let g = task("open field", "openfield", " protocol A \n")
  var document = WorkspaceDocument(projects:[NativeProject(experiments:[a,b,c,d,e,f,g], videos:[video(a),video(b,"M2",2),video(c,"M3",1),video(e,"M4",1),video(g,"M5",1),video(f,"M6",1)])])
  let outcome = TaskMergePolicy.consolidate(document:&document)
  check(document.projects[0].experiments.count == 4,"blank notes and identical annotated notes merge, different notes/model kept")
  check(outcome.redirects[b.id] == a.id,"stable survivor of blank notes")
  check(outcome.redirects[e.id] == c.id && outcome.redirects[g.id] == c.id,"same notes including trailing whitespace merge")
  check(document.projects[0].videos[1].experimentID == a.id,"blank-note video retargeted")
  check(document.projects[0].videos[3].experimentID == c.id && document.projects[0].videos[4].experimentID == c.id,"annotated video retargeted")
  check(document.projects[0].videos[4].runFolder == "stable-run","runFolder retained")
  check(document.projects[0].experiments[0].groupStyles?.count == 2,"groupStyles retained")
  check(document.projects[0].experiments.contains(where:{$0.id == d.id}),"different assay kept")
  check(document.projects[0].experiments.contains(where:{$0.id == f.id}),"different notes kept")
  check(TaskMergePolicy.sameNotes(nil,"  \n"),"nil and blank equal")
  check(!TaskMergePolicy.sameNotes("Dose A","dose a"),"meaningful case difference retained")
  check(!TaskMergePolicy.sameNotes("A B","A  B"),"internal spacing is retained")
  check(TaskMergePolicy.consolidate(document:&document).redirects.isEmpty,"idempotent")
  let x = task("Cylinder", "openfield", "pilot"); let y = task("Cylinder", "openfield", "pilot")
  var collision = WorkspaceDocument(projects:[NativeProject(experiments:[x,y],videos:[video(x),video(y)])])
  let blocked = TaskMergePolicy.consolidate(document:&collision)
  check(collision.projects[0].experiments.count == 2 && blocked.blocked.contains(y.id),"colliding annotated animal+session cannot merge")
  let h = task("Gait", "openfield", "dose"); let i = task("Gait", "openfield", "dose")
  var groupConflict = WorkspaceDocument(projects:[NativeProject(experiments:[h,i],videos:[video(h,"1",1,"ctl"),video(i,"1",2,"drug")])])
  check(!TaskMergePolicy.consolidate(document:&groupConflict).blocked.isEmpty,"conflicting group metadata cannot merge")
  let j = task("NOR", "openfield", "A");let k = task("NOR", "openfield", "A")
  var otherProjects = WorkspaceDocument(projects:[NativeProject(experiments:[j],videos:[]),NativeProject(experiments:[k],videos:[])])
  check(TaskMergePolicy.consolidate(document:&otherProjects).redirects.isEmpty,"projects kept isolated")
  check(TaskMergePolicy.sameName("  CÝLINDER  ","cylinder"),"name normalization")
  print("PASS: 18 task merge assertions (same name + same note, safety, metadata, idempotence)")
 }
}
