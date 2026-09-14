// qmllint disable missing-property
import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.rogersmitha51.keylight"

  readonly property var keylight: root.bar && root.bar.shell
    ? root.bar.shell.firstPartyServiceFor(root.moduleName)
    : null
  property int wheelAccumulator: 0

  function syncSettings() {
    if (root.keylight) root.keylight.settings = root.settings || ({})
  }

  onKeylightChanged: syncSettings()
  onSettingsChanged: syncSettings()
  Component.onCompleted: Qt.callLater(syncSettings)

  visible: keylight ? keylight.available : false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    active: root.keylight ? root.keylight.brightness > 0 : false
    dimmed: !root.keylight || !root.keylight.available
    tooltipText: {
      if (!root.keylight) return "Keylight unavailable"
      if (root.keylight.lastError) return root.keylight.lastError
      var state = "Keyboard backlight: " + root.keylight.percent + "%"
      if (root.keylight.idleBlankingEnabled)
        state += "\nTurns off after " + root.keylight.idleTimeout + " seconds of inactivity"
      return state + "\nLeft click: cycle · Scroll: adjust · Middle click: toggle · Right click: off"
    }

    onPressed: function(buttonCode) {
      if (!root.keylight) return
      if (buttonCode === Qt.MiddleButton) root.keylight.toggle()
      else if (buttonCode === Qt.RightButton) root.keylight.turnOff()
      else root.keylight.cycle()
    }

    onWheelMoved: function(delta) {
      if (!root.keylight) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      for (var i = 0; i < Math.abs(wheel.steps); i++) {
        if (wheel.steps > 0) root.keylight.increase()
        else root.keylight.decrease()
      }
    }
  }
}
// qmllint enable missing-property
