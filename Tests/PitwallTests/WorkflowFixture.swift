import Foundation

/// A real `local_workflow` stream captured from Claude Code 2.1.319 (2026-11-13, `claude -p --input-format stream-json`,
/// haiku): three reader agents in phase 1, one merge agent in phase 2, stopped with `stop_task` while the merge ran.
/// Long previews and the script were shortened; field names and values are as the CLI sent them.
private let workflowFixtureLines = #"""
{"type":"system","subtype":"task_started","task_id":"we5obch08","run_id":"r1","tool_use_id":"toolu_wf","description":"Three agents each read all txt files; one agent merges them","task_type":"local_workflow","workflow_name":"txt-read-summarize","prompt":"export const meta = { name: 'txt-read-summarize' }"}
{"type":"system","subtype":"task_progress","task_id":"we5obch08","run_id":"r1","tool_use_id":"toolu_wf","description":"Read: reader 1","usage":{"duration_ms":25,"tool_uses":0,"total_tokens":0},"workflow_progress":[{"type":"workflow_phase","index":1,"title":"Read"},{"type":"workflow_phase","index":2,"title":"Summarize"},{"type":"workflow_agent","index":1,"label":"reader 1","agentId":"a1","phaseIndex":1,"phaseTitle":"Read","model":"claude-haiku-5-5","state":"start","attempt":1,"promptPreview":"Read every .txt file"},{"type":"workflow_agent","index":2,"label":"reader 2","phaseIndex":1,"phaseTitle":"Read","state":"start"},{"type":"workflow_agent","index":3,"label":"reader 3","phaseIndex":1,"phaseTitle":"Read","state":"start"}]}
{"type":"system","subtype":"task_progress","task_id":"we5obch08","run_id":"r1","tool_use_id":"toolu_wf","description":"Read: reader 3","usage":{"duration_ms":900,"tool_uses":2,"total_tokens":5000}}
{"type":"system","subtype":"task_progress","task_id":"we5obch08","run_id":"r1","tool_use_id":"toolu_wf","description":"Read: reader 1","usage":{"duration_ms":4388,"tool_uses":12,"total_tokens":86067},"workflow_progress":[{"type":"workflow_phase","index":1,"title":"Read"},{"type":"workflow_phase","index":2,"title":"Summarize"},{"type":"workflow_agent","index":1,"label":"reader 1","agentId":"a1","phaseIndex":1,"phaseTitle":"Read","state":"done","tokens":29064,"toolCalls":5,"durationMs":4376,"lastToolName":"Read","lastToolSummary":"/tmp/f4.txt","resultPreview":"f1.txt: one-line note"},{"type":"workflow_agent","index":2,"label":"reader 2","agentId":"a2","phaseIndex":1,"phaseTitle":"Read","state":"progress","tokens":28518,"toolCalls":5,"lastToolName":"Read","lastToolSummary":"/tmp/f4.txt"},{"type":"workflow_agent","index":3,"label":"reader 3","agentId":"a3","phaseIndex":1,"phaseTitle":"Read","state":"progress","tokens":28485,"toolCalls":2,"lastToolName":"Bash","lastToolSummary":"for f in f1.txt"}]}
{"type":"system","subtype":"task_progress","task_id":"we5obch08","run_id":"r1","tool_use_id":"toolu_wf","description":"Three agents each read all txt files; one agent merges them","usage":{"duration_ms":9008,"tool_uses":16,"total_tokens":113517},"workflow_progress":[{"type":"workflow_phase","index":1,"title":"Read"},{"type":"workflow_phase","index":2,"title":"Summarize"},{"type":"workflow_agent","index":1,"label":"reader 1","agentId":"a1","phaseIndex":1,"phaseTitle":"Read","state":"done","tokens":29064},{"type":"workflow_agent","index":2,"label":"reader 2","agentId":"a2","phaseIndex":1,"phaseTitle":"Read","state":"done","tokens":28974},{"type":"workflow_agent","index":3,"label":"reader 3","agentId":"a3","phaseIndex":1,"phaseTitle":"Read","state":"done","tokens":29169},{"type":"workflow_agent","index":4,"label":"merge","agentId":"a4","phaseIndex":2,"phaseTitle":"Summarize","state":"error","endedWithRun":"stopped","error":"Stopped because the workflow was stopped","tokens":26310}]}
{"type":"system","subtype":"task_updated","task_id":"we5obch08","run_id":"r1","patch":{"status":"killed","end_time":1794568040626}}
{"type":"system","subtype":"task_notification","task_id":"we5obch08","run_id":"r1","tool_use_id":"toolu_wf","status":"stopped","output_file":"/tmp/we5obch08.output","summary":"Three agents each read all txt files; one agent merges them"}
{"type":"system","subtype":"background_tasks_changed","tasks":[]}
"""#

/// Events up to and including `count` lines of the captured stream.
func workflowFixtureEvents(upTo count: Int = .max) -> [[String: Any]] {
    workflowFixtureLines.split(separator: "\n").prefix(count).map {
        try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
    }
}
