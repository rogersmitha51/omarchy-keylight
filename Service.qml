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

  readonly property string helperPath: String(Qt.resolvedUrl("bin/keylight")).replace(/^file:\/\//, "")
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
    if (!wasAvailable) console.log("keylight ready device=" + root.deviceName + " timeout=" + root.idleTimeout)
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
    worker.command = root.commandFor(action)
    worker.running = true
  }

  function cycle() { enqueue("cycle") }
  function toggle() { enqueue("toggle") }
  function turnOff() { enqueue("off") }
  function increase() { enqueue("up") }
  function decrease() { enqueue("down") }
  function refresh() { enqueue("status") }

  onConfiguredDeviceChanged: refresh()
  onIdleBlankingEnabledChanged: {
    if (!idleBlankingEnabled && autoBlanked) enqueue("idle-restore")
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
    onIsIdleChanged: {
      console.log("keylight activity=" + (isIdle ? "idle" : "active"))
      if (isIdle) root.enqueue("idle-off")
      else root.enqueue("idle-restore")
    }
  }

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: worker
    property string action: ""
    property string outputText: ""
    property string errorText: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: worker.outputText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: worker.errorText = text
    }
    onStarted: {
      outputText = ""
      errorText = ""
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0) root.applyStatus(outputText)
      else if (exitCode === 3) root.applyStatus("unavailable")
      else root.lastError = String(errorText || ("Keylight action failed: " + worker.action)).trim()
      Qt.callLater(root.startNext)
    }
  }
}
