import QtQuick
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var settings: ({})

  property bool available: false
  property string deviceName: ""
  property int brightness: 0
  property int maximumBrightness: 0
  property int percent: 0
  property bool autoBlanked: false
  property string lastError: ""
  property var actionQueue: []
  property bool restoreAfterUnlock: false
  property bool startupChecked: false

  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("bin/keylight")).replace(/^file:\/\//, ""))
  readonly property string configuredDevice: String(setting("device", "") || "").trim()
  readonly property bool idleBlankingEnabled: setting("idleBlanking", true) === true
  readonly property int idleTimeout: boundedInteger("idleTimeout", 5, 5, 3600)
  readonly property int refreshInterval: boundedInteger("refreshInterval", 2000, 500, 60000)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boundedInteger(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function commandFor(action) {
    var command = [root.helperPath, action]
    if (root.configuredDevice !== "") command.push(root.configuredDevice)
    return command
  }

  function applyStatus(output) {
    var wasAvailable = root.available
    var fields = String(output || "").trim().split("\t")
    if (fields.length < 6 || fields[0] !== "available") {
      root.available = false
      root.deviceName = ""
      root.brightness = 0
      root.maximumBrightness = 0
      root.percent = 0
      root.autoBlanked = false
      return
    }

    root.available = true
    root.deviceName = fields[1]
    root.brightness = Math.max(0, parseInt(fields[2], 10) || 0)
    root.maximumBrightness = Math.max(0, parseInt(fields[3], 10) || 0)
    root.percent = Math.max(0, Math.min(100, parseInt(fields[4], 10) || 0))
    root.autoBlanked = fields[5] === "1"
    root.lastError = ""
    if (!wasAvailable) {
      console.log("keylight ready device=" + root.deviceName + " timeout=" + root.idleTimeout)
      root.checkStartupState()
    }
  }

  // A light blanked by a lock is restored by the shell's own wake process,
  // which only has a brightnessctl save to work from; that save is a stale
  // zero when the light was already off when the lock was taken. The helper
  // still holds the level the user chose, so settle the two once per start.
  function checkStartupState() {
    if (root.startupChecked || !root.autoBlanked) return
    root.startupChecked = true
    startupLockReader.running = true
  }

  function enqueue(action) {
    var queue = root.actionQueue.slice()
    if (action === "status" && (worker.running || queue.indexOf("status") !== -1)) return
    queue.push(action)
    root.actionQueue = queue
    startNext()
  }

  function startNext() {
    if (worker.running || root.actionQueue.length === 0) return
    var queue = root.actionQueue.slice()
    var action = queue.shift()
    root.actionQueue = queue
    worker.action = action
    worker.startedSuccessfully = false
    worker.command = root.commandFor(action)
    worker.running = true
  }

  function cycle() { enqueue("cycle") }
  function toggle() { enqueue("toggle") }
  function turnOff() { enqueue("off") }
  function increase() { enqueue("up") }
  function decrease() { enqueue("down") }
  function refresh() { enqueue("status") }
  function checkLockState() {
    if (!root.restoreAfterUnlock || lockStateReader.running) return
    lockStateReader.outputText = ""
    lockStateReader.running = true
  }

  function handleActivity(isIdle) {
    console.log("keylight activity=" + (isIdle ? "idle" : "active"))
    if (isIdle) {
      root.restoreAfterUnlock = false
      unlockPoll.stop()
      root.enqueue("idle-off")
    } else {
      root.restoreAfterUnlock = true
      root.checkLockState()
    }
  }

  onConfiguredDeviceChanged: refresh()
  onIdleBlankingEnabledChanged: {
    if (!idleBlankingEnabled) {
      restoreAfterUnlock = false
      unlockPoll.stop()
      if (autoBlanked) enqueue("idle-restore")
    }
  }

  Component.onCompleted: {
    console.log("keylight service starting")
    Qt.callLater(refresh)
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.idleBlankingEnabled && root.available
    timeout: root.idleTimeout
    respectInhibitors: false
    onIsIdleChanged: root.handleActivity(isIdle)
  }

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
  Timer {
    id: unlockPoll
    interval: 250
    repeat: false
    onTriggered: root.checkLockState()
  }

  Process {
    id: lockStateReader
    property string outputText: ""
    command: ["omarchy-shell", "lock", "isLocked"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: lockStateReader.outputText = text
    }
    onExited: function(exitCode) {
      if (!root.restoreAfterUnlock) return
      if (exitCode === 0 && String(outputText || "").trim() === "true") {
        unlockPoll.restart()
      } else {
        root.restoreAfterUnlock = false
        root.enqueue("idle-restore")
      }
    }
  }

  Process {
    id: startupLockReader
    command: ["omarchy-shell", "lock", "isLocked"]
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.autoBlanked) return
      // The light is dark because of an automatic blank, not a deliberate off.
      // If the lock is still up, restore when it lifts, so the shell's own
      // wake restore runs first; if it already lifted, restore now.
      root.restoreAfterUnlock = true
      root.checkLockState()
    }
  }


  Process {
    id: worker
    property string action: ""
    property string outputText: ""
    property string errorText: ""
    property bool startedSuccessfully: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: worker.outputText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: worker.errorText = text
    }
    onStarted: {
      startedSuccessfully = true
      outputText = ""
      errorText = ""
    }
    onRunningChanged: {
      if (running || action === "" || startedSuccessfully) return
      root.lastError = "Keylight helper could not be started"
      action = ""
      Qt.callLater(root.startNext)
    }
    onExited: function(exitCode, exitStatus) {
      var completedAction = action
      action = ""
      if (exitCode === 0) root.applyStatus(outputText)
      else if (exitCode === 3) root.applyStatus("unavailable")
      else root.lastError = String(errorText || ("Keylight action failed: " + completedAction)).trim()
      Qt.callLater(root.startNext)
    }
  }
}
