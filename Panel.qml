import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "sing-box-dashboard"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var parentWidget: null

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string scriptPath: Qt.resolvedUrl("client.py").toString().replace(/^file:\/\//, "")

  property string currentTab: "overview"
  property var expandedGroups: ({})
  property string searchConnection: ""
  property string selectedLogLevel: "info"
  property string searchLog: ""
  property bool logsPaused: false
  property var connectionsList: []
  property var logsList: []

  readonly property var displayedLogs: {
    var list = root.logsList || []
    var q = (root.searchLog || "").trim().toLowerCase()
    if (!q) return list
    return list.filter(function(item) {
      var plain = ((item.level || "") + " " + (item.seq || "") + " " + (item.message || "")).toLowerCase()
      return plain.indexOf(q) !== -1
    })
  }


  property string inputUrl: parentWidget && parentWidget.effectiveUrl ? parentWidget.effectiveUrl : "http://127.0.0.1:9091"
  property string inputPassword: parentWidget && parentWidget.effectivePassword ? parentWidget.effectivePassword : ""
  property bool showPassword: false
  property bool showTrafficSetting: parentWidget ? parentWidget.showTraffic : true
  property string actionMessage: ""

  function isGroupExpanded(expandedMap, groupName, index) {
    if (expandedMap && expandedMap[groupName] !== undefined) {
      return expandedMap[groupName] === true
    }
    return index === 0
  }

  function toggleGroupExpand(groupName, index) {
    var cur = isGroupExpanded(expandedGroups, groupName, index)
    var next = Object.assign({}, expandedGroups)
    next[groupName] = !cur
    expandedGroups = next
  }

  function open() {
    if (parentWidget) {
      inputUrl = parentWidget.effectiveUrl || "http://127.0.0.1:9091"
      inputPassword = parentWidget.effectivePassword || ""
      parentWidget.refreshNow()
    }
    currentTab = "overview"
    fetchConnections()
    fetchGroups()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") {
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    }
    return false
  }

  function setMode(modeName) {
    if (!parentWidget) return
    actionProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "set-mode", modeName]
    actionProc.running = true
    parentWidget.currentMode = modeName
  }

  function selectNode(groupName, nodeName) {
    if (!parentWidget) return
    actionProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "select", groupName, nodeName]
    actionProc.running = true
  }

  function testGroup(groupName) {
    if (!parentWidget) return
    actionProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "urltest", groupName]
    actionProc.running = true
  }

  function testAll() {
    if (!parentWidget) return
    actionProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "urltest"]
    actionProc.running = true
  }

  function closeConn(connId) {
    var url = parentWidget && parentWidget.effectiveUrl ? parentWidget.effectiveUrl : ""
    var pass = parentWidget && parentWidget.effectivePassword ? parentWidget.effectivePassword : ""
    actionProc.command = ["python3", root.scriptPath, "--url", url, "--password", pass, "close-connection", connId]
    actionProc.running = true
    root.connectionsList = (root.connectionsList || []).filter(function(c) { return c.id !== connId })
  }

  function closeAllConns() {
    var url = parentWidget && parentWidget.effectiveUrl ? parentWidget.effectiveUrl : ""
    var pass = parentWidget && parentWidget.effectivePassword ? parentWidget.effectivePassword : ""
    actionProc.command = ["python3", root.scriptPath, "--url", url, "--password", pass, "close-connections"]
    actionProc.running = true
    root.connectionsList = []
  }

  function fetchGroups() {
    if (groupsProc.running) return
    var url = parentWidget && parentWidget.effectiveUrl ? parentWidget.effectiveUrl : ""
    var pass = parentWidget && parentWidget.effectivePassword ? parentWidget.effectivePassword : ""
    groupsProc.command = ["python3", root.scriptPath, "--url", url, "--password", pass, "groups"]
    groupsProc.running = true
  }

  function fetchConnections() {
    if (connectionsProc.running) return
    var url = parentWidget && parentWidget.effectiveUrl ? parentWidget.effectiveUrl : ""
    var pass = parentWidget && parentWidget.effectivePassword ? parentWidget.effectivePassword : ""
    connectionsProc.command = ["python3", root.scriptPath, "--url", url, "--password", pass, "connections"]
    connectionsProc.running = true
  }

  function fetchLogs() {
    if (logsProc.running) return
    var url = parentWidget && parentWidget.effectiveUrl ? parentWidget.effectiveUrl : inputUrl
    var pass = parentWidget && parentWidget.effectivePassword ? parentWidget.effectivePassword : inputPassword
    logsProc.command = ["python3", root.scriptPath, "--url", url, "--password", pass, "logs", root.selectedLogLevel]
    logsProc.running = true
  }

  Timer {
    id: logsAutoRefreshTimer
    interval: 2500
    repeat: true
    running: root.opened && root.currentTab === "logs" && !root.logsPaused
    onTriggered: root.fetchLogs()
  }

  function saveConfig(newUrl, newPass) {
    var trafficStr = (root.parentWidget ? root.parentWidget.showTraffic : root.showTrafficSetting) ? "true" : "false"
    saveProc.command = ["python3", root.scriptPath, "save-config", newUrl, newPass, trafficStr]
    saveProc.running = true
  }

  function setTrafficDisplay(enabled) {
    root.showTrafficSetting = enabled
    if (root.parentWidget) {
      root.parentWidget.showTraffic = enabled
    }
    setTrafficProc.command = ["python3", root.scriptPath, "set-traffic", enabled ? "true" : "false"]
    setTrafficProc.running = true
  }

  Process {
    id: setTrafficProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.parentWidget) root.parentWidget.refreshNow()
      }
    }
  }

  function openDashboard() {
    var dashUrl = "http://127.0.0.1:9091/dashboard/"
    if (parentWidget && parentWidget.effectiveUrl) {
      try {
        var base = parentWidget.effectiveUrl.replace(/\/+$/, "")
        dashUrl = base + "/dashboard/"
      } catch (e) {}
    }
    launchProc.command = ["xdg-open", dashUrl]
    launchProc.running = true
  }

  Process {
    id: saveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.actionMessage = "Config saved"
        if (parentWidget) {
          parentWidget.effectiveUrl = root.inputUrl
          parentWidget.effectivePassword = root.inputPassword
          parentWidget.refreshNow()
        }
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (parentWidget) parentWidget.refreshNow()
        root.fetchGroups()
        if (root.currentTab === "connections") root.fetchConnections()
      }
    }
  }

  Process {
    id: groupsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var res = JSON.parse(raw)
          if (res.online && res.groups && root.parentWidget) {
            root.parentWidget.groupsData = res.groups
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: connectionsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var res = JSON.parse(raw)
          if (res.online && res.connections) {
            root.connectionsList = res.connections
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: logsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var res = JSON.parse(raw)
          if (res.online && res.logs) {
            root.logsList = res.logs
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: launchProc
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(contentCol.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentCol
        width: parent.width
        spacing: Style.space(12)

        // -----------------------------------------------------------
        // Top Bar: Dynamic Title & Quick Actions
        // -----------------------------------------------------------
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: Style.space(22)
            height: Style.space(22)
            Layout.alignment: Qt.AlignVCenter

            Image {
              anchors.fill: parent
              fillMode: Image.PreserveAspectFit
              source: Qt.resolvedUrl("icon.svg")
              sourceSize.width: 64
              sourceSize.height: 64
              smooth: true
            }

            Rectangle {
              width: Style.space(7)
              height: Style.space(7)
              radius: width / 2
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              color: root.parentWidget && root.parentWidget.online ? "#4caf50" : (root.parentWidget && root.parentWidget.httpStatus === 401 ? "#ff9800" : "#f44336")
              border.width: 1
              border.color: "#1e1e20"
            }
          }

          Text {
            text: root.currentTab === "groups" ? "Groups" : (root.currentTab === "connections" ? "Connections" : (root.currentTab === "logs" ? "Logs" : (root.currentTab === "settings" ? "Settings" : "Overview")))
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            color: root.foreground
            Layout.fillWidth: true
          }

          // Test Speed Action
          Button {
            iconText: "󰓅"
            tooltipText: "Test latency on groups"
            onClicked: root.testAll()
          }

          // Refresh button
          Button {
            iconText: "󰑐"
            tooltipText: "Refresh sing-box status"
            iconSpinning: root.parentWidget ? root.parentWidget.busy : false
            onClicked: {
              if (root.parentWidget) root.parentWidget.refreshNow()
              root.fetchGroups()
              if (root.currentTab === "connections") root.fetchConnections()
              if (root.currentTab === "logs") root.fetchLogs()
            }
          }

          // Settings shortcut button
          Button {
            iconText: "󰒓"
            tooltipText: "Configure API settings"
            selected: root.currentTab === "settings"
            onClicked: root.currentTab = (root.currentTab === "settings" ? "overview" : "settings")
          }
        }

        // Navigation Tabs Row
        RowLayout {
          width: parent.width
          spacing: Style.space(4)

          Button {
            text: "Overview"
            iconText: "󰕮"
            selected: root.currentTab === "overview"
            bordered: true
            Layout.fillWidth: true
            onClicked: root.currentTab = "overview"
          }

          Button {
            text: "Groups"
            iconText: "󰒍"
            selected: root.currentTab === "groups"
            bordered: true
            Layout.fillWidth: true
            onClicked: {
              root.currentTab = "groups"
              root.fetchGroups()
            }
          }

          Button {
            text: "Connections"
            iconText: "󰌘"
            selected: root.currentTab === "connections"
            bordered: true
            Layout.fillWidth: true
            onClicked: {
              root.currentTab = "connections"
              root.fetchConnections()
            }
          }

          Button {
            text: "Logs"
            iconText: "󰌱"
            selected: root.currentTab === "logs"
            bordered: true
            Layout.fillWidth: true
            onClicked: {
              root.currentTab = "logs"
              root.fetchLogs()
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        // -----------------------------------------------------------
        // TAB 1: OVERVIEW (EXACTLY MATCHING OFFICIAL sing-box-dashboard)
        // -----------------------------------------------------------
        Column {
          id: overviewTabCol
          width: parent.width
          spacing: Style.space(12)
          visible: root.currentTab === "overview"

          // 2x2 Grid of Cards: Upload, Download, Status, Connections
          Grid {
            id: cardsGrid
            columns: 2
            spacing: Style.space(12)
            width: parent.width

            // 1. Upload Traffic Card
            Rectangle {
              id: uploadCard
              width: (parent.width - Style.space(12)) / 2
              implicitHeight: uploadCol.implicitHeight + Style.space(24)
              height: implicitHeight
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              radius: Style.space(12)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
              border.width: 1

              Column {
                id: uploadCol
                x: Style.space(14)
                y: Style.space(12)
                width: parent.width - Style.space(28)
                spacing: Style.space(4)

                // Header
                Row {
                  spacing: Style.space(6)
                  Text {
                    text: "󰕒"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption * 1.1
                    color: root.dim
                  }
                  Text {
                    text: "Upload"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    font.bold: true
                    color: root.foreground
                  }
                }

                // Primary Metric
                Text {
                  text: (root.parentWidget ? Model.formatBytes(root.parentWidget.uploadRate) : "0 B") + "/s"
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(24)
                  font.bold: true
                  color: root.foreground
                }

                // Subtitle Metric
                Text {
                  text: root.parentWidget ? Model.formatBytes(root.parentWidget.uploadTotal) : "0 B"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }

                Item { width: 1; height: Style.space(4) }

                // Sparkline
                Canvas {
                  id: uploadSparkline
                  width: parent.width
                  height: Style.space(46)

                  property var history: root.parentWidget ? root.parentWidget.uplinkHistory : []
                  onHistoryChanged: requestPaint()
                  onWidthChanged: requestPaint()
                  Component.onCompleted: requestPaint()

                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var w = width
                    var h = height
                    var pts = history || []
                    if (w <= 0 || h <= 0) return

                    if (pts.length < 2) {
                      ctx.beginPath()
                      ctx.moveTo(0, h - 3)
                      ctx.lineTo(w, h - 3)
                      ctx.strokeStyle = "#0084ff"
                      ctx.lineWidth = 2.0
                      ctx.stroke()
                      return
                    }

                    var maxVal = 1
                    for (var i = 0; i < pts.length; i++) {
                      if (pts[i] > maxVal) maxVal = pts[i]
                    }
                    maxVal = maxVal * 1.25

                    var step = w / Math.max(pts.length - 1, 1)

                    ctx.beginPath()
                    ctx.moveTo(0, h)
                    for (var j = 0; j < pts.length; j++) {
                      var x = j * step
                      var y = h - 3 - (pts[j] / maxVal) * (h - 8)
                      ctx.lineTo(x, y)
                    }
                    ctx.lineTo((pts.length - 1) * step, h)
                    ctx.closePath()
                    ctx.fillStyle = "rgba(0, 132, 255, 0.15)"
                    ctx.fill()

                    ctx.beginPath()
                    for (var k = 0; k < pts.length; k++) {
                      var px = k * step
                      var py = h - 3 - (pts[k] / maxVal) * (h - 8)
                      if (k === 0) ctx.moveTo(px, py)
                      else ctx.lineTo(px, py)
                    }
                    ctx.strokeStyle = "#0084ff"
                    ctx.lineWidth = 2.0
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    ctx.stroke()
                  }
                }
              }
            }

            // 2. Download Traffic Card
            Rectangle {
              id: downloadCard
              width: (parent.width - Style.space(12)) / 2
              implicitHeight: downloadCol.implicitHeight + Style.space(24)
              height: implicitHeight
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              radius: Style.space(12)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
              border.width: 1

              Column {
                id: downloadCol
                x: Style.space(14)
                y: Style.space(12)
                width: parent.width - Style.space(28)
                spacing: Style.space(4)

                // Header
                Row {
                  spacing: Style.space(6)
                  Text {
                    text: "󰇚"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption * 1.1
                    color: root.dim
                  }
                  Text {
                    text: "Download"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    font.bold: true
                    color: root.foreground
                  }
                }

                // Primary Metric
                Text {
                  text: (root.parentWidget ? Model.formatBytes(root.parentWidget.downloadRate) : "0 B") + "/s"
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(24)
                  font.bold: true
                  color: root.foreground
                }

                // Subtitle Metric
                Text {
                  text: root.parentWidget ? Model.formatBytes(root.parentWidget.downloadTotal) : "0 B"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }

                Item { width: 1; height: Style.space(4) }

                // Sparkline
                Canvas {
                  id: downloadSparkline
                  width: parent.width
                  height: Style.space(46)

                  property var history: root.parentWidget ? root.parentWidget.downlinkHistory : []
                  onHistoryChanged: requestPaint()
                  onWidthChanged: requestPaint()
                  Component.onCompleted: requestPaint()

                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var w = width
                    var h = height
                    var pts = history || []
                    if (w <= 0 || h <= 0) return

                    if (pts.length < 2) {
                      ctx.beginPath()
                      ctx.moveTo(0, h - 3)
                      ctx.lineTo(w, h - 3)
                      ctx.strokeStyle = "#0084ff"
                      ctx.lineWidth = 2.0
                      ctx.stroke()
                      return
                    }

                    var maxVal = 1
                    for (var i = 0; i < pts.length; i++) {
                      if (pts[i] > maxVal) maxVal = pts[i]
                    }
                    maxVal = maxVal * 1.25

                    var step = w / Math.max(pts.length - 1, 1)

                    ctx.beginPath()
                    ctx.moveTo(0, h)
                    for (var j = 0; j < pts.length; j++) {
                      var x = j * step
                      var y = h - 3 - (pts[j] / maxVal) * (h - 8)
                      ctx.lineTo(x, y)
                    }
                    ctx.lineTo((pts.length - 1) * step, h)
                    ctx.closePath()
                    ctx.fillStyle = "rgba(0, 132, 255, 0.15)"
                    ctx.fill()

                    ctx.beginPath()
                    for (var k = 0; k < pts.length; k++) {
                      var px = k * step
                      var py = h - 3 - (pts[k] / maxVal) * (h - 8)
                      if (k === 0) ctx.moveTo(px, py)
                      else ctx.lineTo(px, py)
                    }
                    ctx.strokeStyle = "#0084ff"
                    ctx.lineWidth = 2.0
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    ctx.stroke()
                  }
                }
              }
            }

            // 3. Status Card (Memory, Goroutines)
            Rectangle {
              id: statusCard
              width: (parent.width - Style.space(12)) / 2
              implicitHeight: statusCol.implicitHeight + Style.space(24)
              height: implicitHeight
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              radius: Style.space(12)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
              border.width: 1

              Column {
                id: statusCol
                x: Style.space(14)
                y: Style.space(12)
                width: parent.width - Style.space(28)
                spacing: Style.space(10)

                // Header
                Row {
                  spacing: Style.space(6)
                  Text {
                    text: "󰍛"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption * 1.1
                    color: root.dim
                  }
                  Text {
                    text: "Status"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    font.bold: true
                    color: root.foreground
                  }
                }

                // Line 1: Memory
                Item {
                  width: parent.width
                  height: Style.space(20)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Memory"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    color: root.dim
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatBytes(root.parentWidget ? root.parentWidget.memory : 0)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    font.bold: true
                    color: root.foreground
                  }
                }

                // Line 2: Goroutines
                Item {
                  width: parent.width
                  height: Style.space(20)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Goroutines"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    color: root.dim
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(root.parentWidget ? root.parentWidget.goroutines : 0)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    font.bold: true
                    color: root.foreground
                  }
                }
              }
            }

            // 4. Connections Card (Inbound, Outbound)
            Rectangle {
              id: connCard
              width: (parent.width - Style.space(12)) / 2
              implicitHeight: connCol.implicitHeight + Style.space(24)
              height: implicitHeight
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              radius: Style.space(12)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
              border.width: 1

              Column {
                id: connCol
                x: Style.space(14)
                y: Style.space(12)
                width: parent.width - Style.space(28)
                spacing: Style.space(10)

                // Header
                Row {
                  spacing: Style.space(6)
                  Text {
                    text: "󰛳"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption * 1.1
                    color: root.dim
                  }
                  Text {
                    text: "Connections"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    font.bold: true
                    color: root.foreground
                  }
                }

                // Line 1: Inbound
                Item {
                  width: parent.width
                  height: Style.space(20)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Inbound"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    color: root.dim
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(root.parentWidget ? root.parentWidget.connectionsIn : 0)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    font.bold: true
                    color: root.foreground
                  }
                }

                // Line 2: Outbound
                Item {
                  width: parent.width
                  height: Style.space(20)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Outbound"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    color: root.dim
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(root.parentWidget ? root.parentWidget.connectionsOut : 0)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 1.05
                    font.bold: true
                    color: root.foreground
                  }
                }
              }
            }
          }

          // 5. Mode Card (Wide Card matching screenshot)
          Rectangle {
            id: modeCard
            width: parent.width
            implicitHeight: modeCol.implicitHeight + Style.space(24)
            height: implicitHeight
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            radius: Style.space(12)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
            border.width: 1

            Column {
              id: modeCol
              x: Style.space(14)
              y: Style.space(12)
              width: parent.width - Style.space(28)
              spacing: Style.space(10)

              // Header
              Row {
                spacing: Style.space(6)
                Text {
                  text: "󰑮"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption * 1.1
                  color: root.dim
                }
                Text {
                  text: "Mode"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption * 1.05
                  font.bold: true
                  color: root.foreground
                }
              }

              // Segmented Container
              Rectangle {
                width: parent.width
                height: Style.space(38)
                color: "#141416"
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                border.width: 1
                radius: Style.space(8)

                Row {
                  id: modeRow
                  anchors.fill: parent
                  anchors.margins: Style.space(3)
                  spacing: Style.space(2)

                  property var modes: ["rule", "direct", "global"]
                  property real itemWidth: (width - (modes.length - 1) * spacing) / modes.length

                  Repeater {
                    model: modeRow.modes

                    Rectangle {
                      id: modeBtn
                      width: modeRow.itemWidth
                      height: modeRow.height
                      radius: Style.space(6)
                      property bool isSelected: root.parentWidget && root.parentWidget.currentMode.toLowerCase() === modelData.toLowerCase()

                      color: isSelected ? "#2c2c2e" : (modeMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.05) : "transparent")
                      border.color: isSelected ? Qt.rgba(255, 255, 255, 0.15) : "transparent"
                      border.width: isSelected ? 1 : 0

                      Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption * 1.05
                        font.bold: modeBtn.isSelected
                        color: modeBtn.isSelected ? "#ffffff" : root.dim
                      }

                      MouseArea {
                        id: modeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setMode(modelData)
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // -----------------------------------------------------------
        // TAB 2: GROUPS (MATCHING OFFICIAL sing-box-dashboard GroupsView)
        // -----------------------------------------------------------
        Column {
          id: groupsTabCol
          width: parent.width
          spacing: Style.space(12)
          visible: root.currentTab === "groups"

          Flickable {
            id: groupsFlickable
            width: parent.width
            height: Math.min(groupsCol.implicitHeight, Style.space(520))
            implicitHeight: height
            contentWidth: width
            contentHeight: groupsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: groupsCol
              width: parent.width
              spacing: Style.space(14)

              Repeater {
                model: root.parentWidget && root.parentWidget.groupsData ? root.parentWidget.groupsData : []

                Rectangle {
                  id: groupCardSurface
                  width: parent.width
                  implicitHeight: groupCardInner.implicitHeight + Style.space(24)
                  height: implicitHeight
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                  radius: Style.space(12)
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                  border.width: 1

                  property var groupInfo: modelData
                  property bool isExpanded: root.isGroupExpanded(root.expandedGroups, groupInfo.name, index)
                  property bool isSelectable: String(groupInfo.type || "").toLowerCase() === "selector"

                  Column {
                    id: groupCardInner
                    x: Style.space(14)
                    y: Style.space(12)
                    width: parent.width - Style.space(28)
                    spacing: Style.space(12)

                    // 1. Group Header Row
                    RowLayout {
                      width: parent.width
                      spacing: Style.space(8)

                      Item {
                        Layout.fillWidth: true
                        implicitHeight: groupTitleRow.implicitHeight

                        Row {
                          id: groupTitleRow
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(6)

                          Text {
                            text: groupCardSurface.groupInfo.name || "group"
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.title * 0.95
                            font.bold: true
                            color: root.foreground
                          }

                          Text {
                            text: Model.proxyDisplayType(groupCardSurface.groupInfo.type)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption * 1.05
                            color: root.dim
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleGroupExpand(groupCardSurface.groupInfo.name, index)
                        }
                      }

                      // Node count badge
                      Rectangle {
                        width: countBadgeText.implicitWidth + Style.space(14)
                        height: Style.space(22)
                        radius: Style.space(11)
                        color: "#2c2c2e"

                        Text {
                          id: countBadgeText
                          anchors.centerIn: parent
                          text: groupCardSurface.groupInfo.items ? String(groupCardSurface.groupInfo.items.length) : "0"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          color: root.dim
                        }
                      }

                      // Test Group Button
                      Button {
                        iconText: "󰓅"
                        tooltipText: "Test latency on this group"
                        onClicked: root.testGroup(groupCardSurface.groupInfo.name)
                      }

                      // Expand / Collapse Chevron Button
                      Button {
                        iconText: groupCardSurface.isExpanded ? "󰅃" : "󰅀"
                        tooltipText: groupCardSurface.isExpanded ? "Collapse group" : "Expand group"
                        onClicked: root.toggleGroupExpand(groupCardSurface.groupInfo.name, index)
                      }
                    }

                    // 2. Node Cards Grid (When Expanded)
                    Grid {
                      id: nodesGrid
                      visible: groupCardSurface.isExpanded
                      width: parent.width
                      columns: width >= Style.space(460) ? 4 : 3
                      spacing: Style.space(8)

                      property real cardWidth: Math.floor((width - (columns - 1) * spacing) / columns)

                      Repeater {
                        model: groupCardSurface.groupInfo.items || []

                        Rectangle {
                          id: nodeCardItem
                          width: nodesGrid.cardWidth
                          height: Style.space(58)
                          radius: Style.space(8)

                          property var itemData: modelData
                          property bool isSelected: groupCardSurface.groupInfo.selected === itemData.name
                          property int delayVal: Number(itemData.delay) || 0

                          color: isSelected ? Qt.rgba(0, 132/255, 1, 0.16) : (nodeHoverArea.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "#1c1c1e")
                          border.color: isSelected ? "#0084ff" : (nodeHoverArea.containsMouse ? Qt.rgba(255, 255, 255, 0.22) : Qt.rgba(255, 255, 255, 0.08))
                          border.width: isSelected ? 1.5 : 1

                          Column {
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(4)

                            // Node Tag Name
                            Text {
                              width: parent.width
                              text: nodeCardItem.itemData.name || ""
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption * 1.05
                              font.bold: true
                              color: "#ffffff"
                              elide: Text.ElideRight
                            }

                            // Protocol Type & Delay Text
                            Item {
                              width: parent.width
                              height: Style.space(16)

                              Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: Model.proxyDisplayType(nodeCardItem.itemData.type)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption * 0.9
                                color: "#888888"
                              }

                              Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: Model.delayText(nodeCardItem.delayVal)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption * 0.95
                                font.bold: true
                                color: Model.delayColor(nodeCardItem.delayVal)
                              }
                            }
                          }

                          ToolTip.visible: nodeHoverArea.containsMouse && nodeCardItem.itemData.name.length > 12
                          ToolTip.text: nodeCardItem.itemData.name + (nodeCardItem.delayVal > 0 ? " (" + nodeCardItem.delayVal + "ms)" : "")

                          MouseArea {
                            id: nodeHoverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: groupCardSurface.isSelectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                              if (groupCardSurface.isSelectable) {
                                root.selectNode(groupCardSurface.groupInfo.name, nodeCardItem.itemData.name)
                                groupCardSurface.groupInfo.selected = nodeCardItem.itemData.name
                              }
                            }
                          }
                        }
                      }
                    }

                    // 3. Horizontal Latency Dots (When Collapsed)
                    Flow {
                      id: dotsFlow
                      visible: !groupCardSurface.isExpanded
                      width: parent.width
                      spacing: Style.space(4)

                      Repeater {
                        model: groupCardSurface.groupInfo.items || []

                        Rectangle {
                          id: dotItem
                          width: 11
                          height: 11
                          radius: 2.5

                          property var itemData: modelData
                          property int delayVal: Number(itemData.delay) || 0
                          property bool isSelected: groupCardSurface.groupInfo.selected === itemData.name

                          color: Model.delayColor(delayVal)

                          // Inner white circle for selected node
                          Rectangle {
                            visible: dotItem.isSelected
                            anchors.centerIn: parent
                            width: 4
                            height: 4
                            radius: 2
                            color: "#ffffff"
                          }

                          ToolTip.visible: dotMouse.containsMouse
                          ToolTip.text: dotItem.itemData.name + (dotItem.delayVal > 0 ? " (" + dotItem.delayVal + "ms)" : "")

                          MouseArea {
                            id: dotMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: groupCardSurface.isSelectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                              if (groupCardSurface.isSelectable) {
                                root.selectNode(groupCardSurface.groupInfo.name, dotItem.itemData.name)
                                groupCardSurface.groupInfo.selected = dotItem.itemData.name
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Empty groups fallback
              Text {
                visible: !root.parentWidget || !root.parentWidget.groupsData || root.parentWidget.groupsData.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Style.space(40)
                text: "No outbound groups found. Click refresh to query sing-box API."
                font.family: root.fontFamily
                color: root.dim
              }
            }
          }
        }

        // -----------------------------------------------------------
        // TAB 3: CONNECTIONS
        // -----------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.currentTab === "connections"

          // Filter & Actions Row
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: connSearchField
              placeholderText: "Search"
              Layout.fillWidth: true
              text: root.searchConnection
              onTextChanged: root.searchConnection = text
            }

            Button {
              text: "Close All"
              iconText: "󰅙"
              tooltipText: "Terminate all active connections"
              onClicked: root.closeAllConns()
            }

            Button {
              iconText: "󰑐"
              tooltipText: "Refresh active connections"
              iconSpinning: connectionsProc.running
              onClicked: root.fetchConnections()
            }
          }

          // Connections Count Summary
          Text {
            text: "Active: " + (root.connectionsList ? root.connectionsList.length : 0) + " tracked connections"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.dim
          }

          // Connections Scrollable List
          Flickable {
            id: connFlickable
            width: parent.width
            height: Math.min(connsCol.implicitHeight, Style.space(520))
            implicitHeight: height
            contentWidth: width
            contentHeight: connsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: connsCol
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: {
                  if (!root.connectionsList) return []
                  if (!root.searchConnection) return root.connectionsList
                  var q = root.searchConnection.trim().toLowerCase()
                  return root.connectionsList.filter(function(c) {
                    return (c.host && c.host.toLowerCase().indexOf(q) !== -1) ||
                           (c.destination && c.destination.toLowerCase().indexOf(q) !== -1) ||
                           (c.route && c.route.toLowerCase().indexOf(q) !== -1) ||
                           (c.outbound && c.outbound.toLowerCase().indexOf(q) !== -1) ||
                           (c.inbound && c.inbound.toLowerCase().indexOf(q) !== -1) ||
                           (c.network && c.network.toLowerCase().indexOf(q) !== -1)
                  })
                }

                Rectangle {
                  id: connCardItem
                  width: parent.width
                  implicitHeight: connCardInner.implicitHeight + Style.space(20)
                  height: implicitHeight
                  color: connHoverArea.containsMouse ? Qt.rgba(255, 255, 255, 0.07) : "#1c1c1e"
                  radius: Style.space(10)
                  border.color: connHoverArea.containsMouse ? Qt.rgba(255, 255, 255, 0.2) : Qt.rgba(255, 255, 255, 0.08)
                  border.width: 1

                  property var cData: modelData

                  Column {
                    id: connCardInner
                    x: Style.space(14)
                    y: Style.space(10)
                    width: parent.width - Style.space(28)
                    spacing: Style.space(8)

                    // Line 1: Header (TCP Badge, Destination Host, Active Badge / Close Button)
                    RowLayout {
                      width: parent.width
                      spacing: Style.space(8)

                      // Network pill (e.g. TCP, UDP)
                      Rectangle {
                        width: netText.implicitWidth + Style.space(12)
                        height: Style.space(20)
                        radius: Style.space(4)
                        color: "#2c2c2e"

                        Text {
                          id: netText
                          anchors.centerIn: parent
                          text: (connCardItem.cData.network || "TCP").toUpperCase()
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption * 0.85
                          font.bold: true
                          color: "#aaaaaa"
                        }
                      }

                      // Host / Destination (Monospace white text)
                      Text {
                        text: connCardItem.cData.host || connCardItem.cData.destination || "Unknown"
                        font.family: "monospace"
                        font.pixelSize: Style.font.caption * 1.05
                        font.bold: true
                        color: "#ffffff"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }

                      // Close button (visible when hovering)
                      Button {
                        id: closeBtn
                        visible: connHoverArea.containsMouse
                        iconText: "󰅙"
                        tooltipText: "Close this connection"
                        onClicked: root.closeConn(connCardItem.cData.id)
                      }

                      // Active status badge (green pill)
                      Rectangle {
                        visible: !closeBtn.visible
                        width: activeText.implicitWidth + Style.space(16)
                        height: Style.space(20)
                        radius: Style.space(4)
                        color: Qt.rgba(52/255, 211/255, 153/255, 0.15)

                        Text {
                          id: activeText
                          anchors.centerIn: parent
                          text: "Active"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption * 0.85
                          font.bold: true
                          color: "#34d399"
                        }
                      }
                    }

                    // Line 2: 3 Columns matching official dashboard
                    RowLayout {
                      width: parent.width

                      // Col 1: Transfer Rates (↑ 0 B/s, ↓ 1 KB/s)
                      Column {
                        Layout.preferredWidth: Style.space(110)
                        spacing: Style.space(2)

                        Text {
                          text: connCardItem.cData.upRate || "↑ 0 B/s"
                          font.family: "monospace"
                          font.pixelSize: Style.font.caption * 0.95
                          color: root.dim
                        }

                        Text {
                          text: connCardItem.cData.downRate || "↓ 0 B/s"
                          font.family: "monospace"
                          font.pixelSize: Style.font.caption * 0.95
                          color: root.dim
                        }
                      }

                      // Col 2: Total Transferred (↑ 2.1 KB, ↓ 5.5 KB)
                      Column {
                        Layout.preferredWidth: Style.space(110)
                        spacing: Style.space(2)

                        Text {
                          text: connCardItem.cData.upTotal || "↑ 0 B"
                          font.family: "monospace"
                          font.pixelSize: Style.font.caption * 0.95
                          color: root.dim
                        }

                        Text {
                          text: connCardItem.cData.downTotal || "↓ 0 B"
                          font.family: "monospace"
                          font.pixelSize: Style.font.caption * 0.95
                          color: root.dim
                        }
                      }

                      Item { Layout.fillWidth: true }

                      // Col 3: Inbound & Outbound / Route (tun/tun-in, select)
                      Column {
                        spacing: Style.space(2)

                        Text {
                          anchors.right: parent.right
                          text: connCardItem.cData.inbound || "tun/tun-in"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption * 0.95
                          color: root.dim
                        }

                        Text {
                          anchors.right: parent.right
                          text: connCardItem.cData.route || connCardItem.cData.outbound || "select"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption * 0.95
                          color: root.dim
                        }
                      }
                    }
                  }

                  MouseArea {
                    id: connHoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                  }
                }
              }

              // Empty Connections State
              Text {
                visible: !root.connectionsList || root.connectionsList.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Style.space(40)
                bottomPadding: Style.space(40)
                text: "No active connections"
                font.family: root.fontFamily
                color: root.dim
              }
            }
          }
        }

        // -----------------------------------------------------------
        // TAB 4: LOGS (BEAUTIFIED MONOSPACE MATCHING OFFICIAL DASHBOARD)
        // -----------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.currentTab === "logs"

          // 1. Search Bar & Action Buttons (Pause, Clear, Reload)
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            // Search pill matching screenshot
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(34)
              radius: Style.space(8)
              color: "#1c1c1e"
              border.color: searchLogInput.activeFocus ? "#0084ff" : Qt.rgba(255, 255, 255, 0.08)
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Text {
                  text: "󰍉"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: "#8e8e93"
                }

                TextInput {
                  id: searchLogInput
                  Layout.fillWidth: true
                  text: root.searchLog
                  onTextChanged: root.searchLog = text
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: "#ffffff"
                  clip: true

                  Text {
                    visible: !searchLogInput.text && !searchLogInput.activeFocus
                    text: "Search"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: "#8e8e93"
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Button {
                  visible: !!searchLogInput.text
                  iconText: "✕"
                  padding: 0
                  onClicked: {
                    searchLogInput.text = ""
                    root.searchLog = ""
                  }
                }
              }
            }

            // Pause / Resume Auto-scroll
            Button {
              iconText: root.logsPaused ? "󰐊" : "󰏤"
              tooltipText: root.logsPaused ? "Resume auto-scroll" : "Pause auto-scroll"
              selected: root.logsPaused
              onClicked: root.logsPaused = !root.logsPaused
            }

            // Clear View
            Button {
              iconText: "󰃢"
              tooltipText: "Clear logs view"
              onClicked: root.logsList = []
            }

            // Refresh
            Button {
              iconText: "󰑐"
              tooltipText: "Reload service logs"
              iconSpinning: logsProc.running
              onClicked: root.fetchLogs()
            }
          }

          // 2. Logs Level Filter Row
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: ["info", "warn", "error", "debug", "trace"]

              Button {
                text: modelData.toUpperCase()
                selected: root.selectedLogLevel === modelData
                bordered: true
                Layout.fillWidth: true
                onClicked: {
                  root.selectedLogLevel = modelData
                  root.fetchLogs()
                }
              }
            }
          }

          // 3. Log Console Card (Dark rounded terminal view matching screenshot)
          Rectangle {
            id: logsConsoleCard
            width: parent.width
            height: Style.space(360)
            color: "#161618"
            radius: Style.space(12)
            border.color: Qt.rgba(255, 255, 255, 0.08)
            border.width: 1
            clip: true

            Flickable {
              id: logsFlickable
              anchors.fill: parent
              anchors.margins: Style.space(12)
              contentWidth: Math.max(width, logLinesCol.implicitWidth)
              contentHeight: logLinesCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              onContentHeightChanged: {
                if (!root.logsPaused && contentHeight > height) {
                  contentY = contentHeight - height
                }
              }

              Column {
                id: logLinesCol
                spacing: Style.space(3)

                Repeater {
                  model: root.displayedLogs

                  Text {
                    textFormat: Text.RichText
                    text: Model.formatLogLineHtml(modelData)
                    font.family: "monospace"
                    font.pixelSize: Style.font.caption * 0.92
                    renderType: Text.NativeRendering
                  }
                }

                Text {
                  visible: !root.displayedLogs || root.displayedLogs.length === 0
                  width: logsFlickable.width
                  horizontalAlignment: Text.AlignHCenter
                  topPadding: Style.space(50)
                  text: root.searchLog ? ("No logs matching \"" + root.searchLog + "\"") : ("No log entries for level " + root.selectedLogLevel)
                  font.family: "monospace"
                  font.pixelSize: Style.font.caption
                  color: "#888888"
                }
              }
            }
          }
        }

        // -----------------------------------------------------------
        // TAB 5: SETTINGS
        // -----------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.currentTab === "settings"

          PanelSectionHeader {
            text: "SING-BOX API CONFIGURATION"
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "API Service URL:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.foreground
            }

            TextField {
              id: urlInput
              width: parent.width
              text: root.inputUrl
              placeholderText: "http://127.0.0.1:9091 or http://127.0.0.1:9090"
              onTextChanged: root.inputUrl = text
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "API Secret / Password:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.foreground
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: passInput
                text: root.inputPassword
                password: !root.showPassword
                placeholderText: "Enter sing-box API secret"
                Layout.fillWidth: true
                onTextChanged: root.inputPassword = text
              }

              Button {
                iconText: root.showPassword ? "󰈉" : "󰈈"
                tooltipText: root.showPassword ? "Hide password" : "Show password"
                onClicked: root.showPassword = !root.showPassword
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Save & Connect"
              iconText: "󰆓"
              selected: true
              bordered: true
              Layout.fillWidth: true
              onClicked: root.saveConfig(root.inputUrl, root.inputPassword)
            }

            Button {
              text: "Web Dashboard"
              iconText: "󰖟"
              bordered: true
              Layout.fillWidth: true
              onClicked: root.openDashboard()
            }
          }

          Text {
            visible: Boolean(root.actionMessage)
            text: root.actionMessage
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: "#4caf50"
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          PanelSectionHeader {
            text: "BAR DISPLAY"
            foreground: root.foreground
          }

          Toggle {
            width: parent.width
            label: "Display Traffic in Bar"
            description: "Show real-time upload and download speeds on the top bar"
            foreground: root.foreground
            accent: Style.accent || "#38bdf8"
            fontFamily: root.fontFamily
            checked: root.parentWidget ? root.parentWidget.showTraffic : root.showTrafficSetting
            onClicked: {
              var current = root.parentWidget ? root.parentWidget.showTraffic : root.showTrafficSetting
              root.setTrafficDisplay(!current)
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // Service info banner
          BorderSurface {
            width: parent.width
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            radius: Style.cornerRadius
            leftPadding: Style.space(10)
            rightPadding: Style.space(10)
            topPadding: Style.space(8)
            bottomPadding: Style.space(8)

            ColumnLayout {
              anchors.fill: parent
              spacing: Style.space(2)

              Text {
                text: "sing-box 1.14 Integration"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: root.foreground
              }

              Text {
                text: "Reads sing-box daemon API (port 9091) or Clash API (port 9090). Saved credentials persist to ~/.config/sing-box-dashboard/config.json."
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption * 0.9
                color: root.dim
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }
            }
          }
        }
      }
    }
  }
}
