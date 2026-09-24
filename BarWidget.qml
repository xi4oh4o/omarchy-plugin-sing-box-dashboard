import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "sing-box-dashboard"

  readonly property string configuredUrl: String(setting("url", ""))
  readonly property string configuredPassword: String(setting("password", ""))
  readonly property int configuredInterval: Math.max(1, Number(setting("refreshIntervalSec", 2)))

  property string effectiveUrl: configuredUrl
  property string effectivePassword: configuredPassword

  property bool online: false
  property string errorText: ""
  property int httpStatus: 0
  property string apiType: "daemon"
  property string version: ""
  property string activeNode: ""
  property string currentMode: "Rule"
  property var modeList: ["Rule", "Direct", "Global"]
  property real uploadRate: 0
  property real downloadRate: 0
  property real uploadTotal: 0
  property real downloadTotal: 0
  property int connCount: 0
  property real memory: 0
  property int goroutines: 0
  property string uptime: ""
  property int connectionsIn: 0
  property int connectionsOut: 0
  property var uplinkHistory: []
  property var downlinkHistory: []
  property var groupsData: []
  property bool busy: false

  readonly property var configuredShowTraffic: setting("showTraffic", null)
  property bool showTraffic: configuredShowTraffic !== null ? Boolean(configuredShowTraffic) : true
  property double lastTrafficToggleTime: 0

  function setShowTraffic(enabled) {
    root.lastTrafficToggleTime = Date.now()
    root.showTraffic = enabled
    persistTrafficProc.command = ["python3", root.scriptPath, "set-traffic", enabled ? "true" : "false"]
    persistTrafficProc.running = false
    persistTrafficProc.running = true
  }

  Process {
    id: persistTrafficProc
  }

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color statusColor: online ? "#4caf50" : (httpStatus === 401 ? "#ff9800" : "#f44336")

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggle() {
    togglePanel()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var item = panelLoader.item
    if (!item) return
    if ("bar" in item) item.bar = root.bar
    if ("settings" in item) item.settings = root.settings
    if ("anchorItem" in item) item.anchorItem = button
    if ("hostWidget" in item) item.hostWidget = root
    if ("parentWidget" in item) item.parentWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  readonly property string scriptPath: Qt.resolvedUrl("client.py").toString().replace(/^file:\/\//, "")

  Process {
    id: statusProc
    command: ["python3", root.scriptPath, "--url", root.effectiveUrl, "--password", root.effectivePassword, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var res = JSON.parse(raw)
          root.online = res.online === true
          root.httpStatus = Number(res.status) || (root.online ? 200 : 0)
          root.errorText = String(res.error || "")
          root.apiType = String(res.apiType || "daemon")
          if (res.showTraffic !== undefined && root.configuredShowTraffic === null) {
            if (Date.now() - root.lastTrafficToggleTime > 3000) {
              root.showTraffic = res.showTraffic === true
            }
          }
          if (root.online) {
            root.version = String(res.version || "")
            root.currentMode = Model.normalizeMode(res.mode)
            root.modeList = res.modeList || ["Rule", "Direct", "Global"]
            root.activeNode = String(res.activeNode || "")
            root.uploadRate = Number(res.uploadRate) || 0
            root.downloadRate = Number(res.downloadRate) || 0
            root.uploadTotal = Number(res.uploadTotal) || 0
            root.downloadTotal = Number(res.downloadTotal) || 0
            root.connCount = Number(res.connectionsCount) || 0
            root.connectionsIn = Number(res.connectionsIn) || 0
            root.connectionsOut = Number(res.connectionsOut) || 0
            root.uptime = String(res.uptime || "")
            root.memory = Number(res.memory) || 0
            root.goroutines = Number(res.goroutines) || 0
            root.groupsData = res.groups || []

            var up = Number(res.uploadRate) || 0
            var down = Number(res.downloadRate) || 0

            var upHist = root.uplinkHistory.slice()
            upHist.push(up)
            if (upHist.length > 30) upHist.shift()
            root.uplinkHistory = upHist

            var downHist = root.downlinkHistory.slice()
            downHist.push(down)
            if (downHist.length > 30) downHist.shift()
            root.downlinkHistory = downHist
          }
        } catch (e) {
          root.online = false
          root.errorText = "Parse error"
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.configuredInterval * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      if (!statusProc.running) {
        root.busy = true
        statusProc.command = ["python3", root.scriptPath, "--url", root.effectiveUrl, "--password", root.effectivePassword, "status"]
        statusProc.running = true
      }
    }
  }

  function refreshNow() {
    if (!statusProc.running) {
      root.busy = true
      statusProc.command = ["python3", root.scriptPath, "--url", root.effectiveUrl, "--password", root.effectivePassword, "status"]
      statusProc.running = true
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  readonly property string trafficLabel: {
    if (root.vertical || !root.showTraffic) {
      if (root.httpStatus === 401) return "Auth Required"
      return ""
    }
    if (root.online) {
      return "↑ " + Model.formatRate(root.uploadRate) + "  ↓ " + Model.formatRate(root.downloadRate)
    }
    if (root.httpStatus === 401) {
      return "Auth Required"
    }
    return "sing-box"
  }

  readonly property real openPanelIndicatorWidth: Math.max(Style.space(16), contentRow.implicitWidth)
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  implicitWidth: root.vertical ? root.barSize : Math.max(root.barSize, contentRow.implicitWidth + Style.space(17))
  implicitHeight: root.barSize

  IpcHandler {
    target: "sing-box-dashboard"

    function refresh() { root.refreshNow() }
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.togglePanel() }
    function toggleTraffic() { root.setShowTraffic(!root.showTraffic) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    fixedWidth: root.implicitWidth
    fixedHeight: root.implicitHeight
    active: root.opened
    useActiveColor: false
    activeColor: root.foreground
    Component.onCompleted: root.injectPanel()
    tooltipText: root.online
      ? ("sing-box [" + root.currentMode + "]\n" +
         (root.activeNode ? "Node: " + root.activeNode + "\n" : "") +
         "↑ " + Model.formatRate(root.uploadRate) + "  ↓ " + Model.formatRate(root.downloadRate) + "\n" +
         "Click to open sing-box panel")
      : (root.httpStatus === 401
          ? "sing-box: 401 Unauthorized\nClick to configure API password"
          : "sing-box: Offline\nClick to check connection")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refreshNow()
      else root.togglePanel()
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      SingBoxIcon {
        id: boxIcon
        width: Style.space(16)
        height: Style.space(16)
        iconSize: Style.space(16)
        color: root.foreground
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: labelText
        visible: root.trafficLabel !== ""
        text: root.trafficLabel
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        color: root.foreground
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
      }
    }
  }
}
