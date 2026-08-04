import Testing
import Foundation
@testable import Domain

@Suite
struct ClaudeSessionTests {
    @Test
    func `new session starts in active phase`() {
        let session = ClaudeSession(id: "test", cwd: "/tmp")

        #expect(session.phase == .active)
        #expect(session.activeSubagentCount == 0)
        #expect(session.completedTaskCount == 0)
        #expect(session.isActive == true)
        #expect(session.endedAt == nil)
    }

    @Test
    func `subagent start changes phase to subagentsWorking`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStarted()

        #expect(session.phase == .subagentsWorking)
        #expect(session.activeSubagentCount == 1)
    }

    @Test
    func `multiple subagents can be active`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStarted()
        session.subagentStarted()
        session.subagentStarted()

        #expect(session.activeSubagentCount == 3)
        #expect(session.phase == .subagentsWorking)
    }

    @Test
    func `subagent stop returns to active when no subagents remain`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStarted()
        session.subagentStopped()

        #expect(session.activeSubagentCount == 0)
        #expect(session.phase == .active)
    }

    @Test
    func `subagent stop stays subagentsWorking when subagents remain`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStarted()
        session.subagentStarted()
        session.subagentStopped()

        #expect(session.activeSubagentCount == 1)
        #expect(session.phase == .subagentsWorking)
    }

    @Test
    func `subagent count does not go below zero`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStopped()
        session.subagentStopped()

        #expect(session.activeSubagentCount == 0)
        #expect(session.phase == .active)
    }

    @Test
    func `task completed increments count`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.taskCompleted()
        session.taskCompleted()
        session.taskCompleted()

        #expect(session.completedTaskCount == 3)
    }

    @Test
    func `stop sets phase to stopped and clears subagents`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.subagentStarted()
        session.subagentStarted()

        session.stop()

        #expect(session.phase == .stopped)
        #expect(session.activeSubagentCount == 0)
        #expect(session.isActive == true) // stopped but not ended
    }

    @Test
    func `end sets phase to ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        let endDate = Date()

        session.end(at: endDate)

        #expect(session.phase == .ended)
        #expect(session.isActive == false)
        #expect(session.endedAt == endDate)
        #expect(session.activeSubagentCount == 0)
    }

    @Test
    func `duration description formats correctly for seconds`() {
        let start = Date()
        var session = ClaudeSession(id: "test", cwd: "/tmp", startedAt: start)
        session.end(at: start.addingTimeInterval(45))

        #expect(session.durationDescription == "45s")
    }

    @Test
    func `duration description formats correctly for minutes`() {
        let start = Date()
        var session = ClaudeSession(id: "test", cwd: "/tmp", startedAt: start)
        session.end(at: start.addingTimeInterval(125)) // 2m 5s

        #expect(session.durationDescription == "2m 5s")
    }

    @Test
    func `duration description formats correctly for hours`() {
        let start = Date()
        var session = ClaudeSession(id: "test", cwd: "/tmp", startedAt: start)
        session.end(at: start.addingTimeInterval(3660)) // 1h 1m

        #expect(session.durationDescription == "1h 1m")
    }

    @Test
    func `identity is based on id`() {
        let session1 = ClaudeSession(id: "abc", cwd: "/tmp")
        let session2 = ClaudeSession(id: "abc", cwd: "/other")

        #expect(session1.id == session2.id)
    }

    // MARK: - Phase Guards

    @Test
    func `subagentStarted revives a stopped session`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.stop()

        session.subagentStarted()

        #expect(session.phase == .subagentsWorking)
        #expect(session.activeSubagentCount == 1)
    }

    @Test
    func `resume returns a stopped session to active`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.stop()

        session.resume()

        #expect(session.phase == .active)
        #expect(session.activeSubagentCount == 0)
    }

    @Test
    func `resume keeps subagentsWorking when subagents are active`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.subagentStarted()

        session.resume()

        #expect(session.phase == .subagentsWorking)
        #expect(session.activeSubagentCount == 1)
    }

    @Test
    func `resume is ignored after ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.end()

        session.resume()

        #expect(session.phase == .ended)
    }

    @Test
    func `subagentStopped is ignored after ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.subagentStarted()
        session.end()

        session.subagentStopped()

        #expect(session.phase == .ended)
        #expect(session.activeSubagentCount == 0)
    }

    @Test
    func `taskCompleted still works after stopped`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.stop()

        session.taskCompleted()

        #expect(session.completedTaskCount == 1)
    }

    @Test
    func `taskCompleted is ignored after ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.end()

        session.taskCompleted()

        #expect(session.completedTaskCount == 0)
    }

    @Test
    func `stop is ignored after ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.end()

        session.stop()

        #expect(session.phase == .ended)
    }

    @Test
    func `phase label returns correct strings`() {
        #expect(ClaudeSession.Phase.active.label == "Active")
        #expect(ClaudeSession.Phase.subagentsWorking.label == "Agents Working")
        #expect(ClaudeSession.Phase.stopped.label == "Stopped")
        #expect(ClaudeSession.Phase.ended.label == "Ended")
    }
}
