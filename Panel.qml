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
  property int activeGroupIndex: 0
  property string searchConnection: ""
  property string selectedLogLevel: "info"
  property var connectionsList: []
  property var logsList: []

  property string inputUrl: parentWidget && parentWidget.effectiveUrl ? parentWidget.effectiveUrl : "http://127.0.0.1:9091"
  property string inputPassword: parentWidget && parentWidget.effectivePassword ? parentWidget.effectivePassword : ""
  property bool showPassword: false
  property string actionMessage: ""

  function open() {
    if (parentWidget) {
      inputUrl = parentWidget.effectiveUrl || "http://127.0.0.1:9091"
      inputPassword = parentWidget.effectivePassword || ""
      parentWidget.refreshNow()
    }
    currentTab = "overview"
    fetchConnections()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    root.opened ? close() : open()
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
    if (!parentWidget) return
    actionProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "close-connection", connId]
    actionProc.running = true
  }

  function closeAllConns() {
    if (!parentWidget) return
    actionProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "close-connections"]
    actionProc.running = true
  }

  function fetchConnections() {
    if (!parentWidget || connectionsProc.running) return
    connectionsProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "connections"]
    connectionsProc.running = true
  }

  function fetchLogs() {
    if (!parentWidget || logsProc.running) return
    logsProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "logs", root.selectedLogLevel]
    logsProc.running = true
  }

  function saveConfig(newUrl, newPass) {
    saveProc.command = ["python3", root.scriptPath, "save-config", newUrl, newPass]
    saveProc.running = true
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
        if (root.currentTab === "connections") root.fetchConnections()
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
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(contentCol.implicitHeight + Style.space(24))

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
        // Top Bar: Title & Navigation Tabs
        // -----------------------------------------------------------
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "󰒋"
            font.family: Style.font.family
            font.pixelSize: Style.font.title * 1.15
            color: root.parentWidget && root.parentWidget.online ? "#4caf50" : (root.parentWidget && root.parentWidget.httpStatus === 401 ? "#ff9800" : "#f44336")
          }

          Text {
            text: "Overview"
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
              if (root.currentTab === "connections") root.fetchConnections()
              if (root.currentTab === "logs") root.fetchLogs()
            }
          }

          // Settings shortcut button (tune icon matching screenshot top-right)
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
              if (root.parentWidget) root.parentWidget.refreshNow()
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

            // -------------------------------------------------------
            // CARD 1: UPLOAD TRAFFIC
            // -------------------------------------------------------
            BorderSurface {
              id: uploadCard
              width: (parent.width - Style.space(12)) / 2
              implicitHeight: uploadCol.implicitHeight + Style.space(24)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              radius: Style.space(12)
              borderSpec: Border.solid(1, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1))

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

                    // Fill polygon
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

                    // Stroke polyline
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

            // -------------------------------------------------------
            // CARD 2: DOWNLOAD TRAFFIC
            // -------------------------------------------------------
            BorderSurface {
              id: downloadCard
              width: (parent.width - Style.space(12)) / 2
              implicitHeight: downloadCol.implicitHeight + Style.space(24)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              radius: Style.space(12)
              borderSpec: Border.solid(1, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1))

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

                    // Fill polygon
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

                    // Stroke polyline
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

            // -------------------------------------------------------
            // CARD 3: STATUS
            // -------------------------------------------------------
            BorderSurface {
              id: statusCard
              width: (parent.width - Style.space(12)) / 2
              implicitHeight: statusCol.implicitHeight + Style.space(24)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              radius: Style.space(12)
              borderSpec: Border.solid(1, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1))

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

            // -------------------------------------------------------
            // CARD 4: CONNECTIONS
            // -------------------------------------------------------
            BorderSurface {
              id: connCard
              width: (parent.width - Style.space(12)) / 2
              implicitHeight: connCol.implicitHeight + Style.space(24)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              radius: Style.space(12)
              borderSpec: Border.solid(1, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1))

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

          // ---------------------------------------------------------
          // CARD 5: MODE (WIDE CARD WITH SEGMENTED SWITCHER)
          // ---------------------------------------------------------
          BorderSurface {
            id: modeCard
            width: parent.width
            implicitHeight: modeCol.implicitHeight + Style.space(24)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            radius: Style.space(12)
            borderSpec: Border.solid(1, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1))

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
        // TAB 2: GROUPS
        // -----------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.currentTab === "groups"

          // Group selector tabs (e.g. select, urltest)
          RowLayout {
            width: parent.width
            spacing: Style.space(6)
            visible: root.parentWidget && root.parentWidget.groupsData && root.parentWidget.groupsData.length > 1

            Repeater {
              model: root.parentWidget ? root.parentWidget.groupsData : []

              Button {
                text: (modelData.name || "group") + " (" + (modelData.items ? modelData.items.length : 0) + ")"
                selected: root.activeGroupIndex === index
                bordered: true
                Layout.fillWidth: true
                onClicked: root.activeGroupIndex = index
              }
            }
          }

          // Active group action header
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            property var curGroup: root.parentWidget && root.parentWidget.groupsData && root.parentWidget.groupsData.length > root.activeGroupIndex
              ? root.parentWidget.groupsData[root.activeGroupIndex] : null

            PanelSectionHeader {
              text: parent.curGroup ? (parent.curGroup.name.toUpperCase() + " (" + parent.curGroup.type + ")") : "OUTBOUND GROUP"
              foreground: root.foreground
              Layout.fillWidth: true
            }

            Button {
              text: "Test Group"
              iconText: "󰓅"
              tooltipText: "Test latency for nodes in this group"
              onClicked: {
                if (parent.curGroup) root.testGroup(parent.curGroup.name)
              }
            }
          }

          // Node List Flickable
          Flickable {
            id: groupFlickable
            width: parent.width
            height: Style.space(340)
            contentWidth: width
            contentHeight: groupNodesCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            property var activeGroup: root.parentWidget && root.parentWidget.groupsData && root.parentWidget.groupsData.length > root.activeGroupIndex
              ? root.parentWidget.groupsData[root.activeGroupIndex] : null

            Column {
              id: groupNodesCol
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: groupFlickable.activeGroup ? groupFlickable.activeGroup.items : []

                BorderSurface {
                  id: nodeCard
                  width: parent.width
                  radius: Style.cornerRadius
                  property bool isSelected: groupFlickable.activeGroup && groupFlickable.activeGroup.selected === modelData.name
                  color: isSelected
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
                    : (nodeMouseArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04))

                  leftPadding: Style.space(10)
                  rightPadding: Style.space(10)
                  topPadding: Style.space(8)
                  bottomPadding: Style.space(8)

                  MouseArea {
                    id: nodeMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (groupFlickable.activeGroup) {
                        root.selectNode(groupFlickable.activeGroup.name, modelData.name)
                        groupFlickable.activeGroup.selected = modelData.name
                      }
                    }
                  }

                  RowLayout {
                    anchors.fill: parent
                    spacing: Style.space(8)

                    Text {
                      text: nodeCard.isSelected ? "󰄬" : "󰄰"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      color: nodeCard.isSelected ? Color.accent : root.dim
                    }

                    ColumnLayout {
                      spacing: Style.space(1)
                      Layout.fillWidth: true

                      Text {
                        text: modelData.name || ""
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: nodeCard.isSelected
                        color: root.foreground
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }

                      Text {
                        text: modelData.type || "proxy"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption * 0.9
                        color: root.dim
                      }
                    }

                    // Delay Badge
                    BorderSurface {
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                      radius: Style.cornerRadius
                      leftPadding: Style.space(6)
                      rightPadding: Style.space(6)
                      topPadding: Style.space(2)
                      bottomPadding: Style.space(2)

                      Text {
                        anchors.centerIn: parent
                        text: Model.delayText(modelData.delay)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: Model.delayColor(modelData.delay, root.foreground, root.dim)
                      }
                    }
                  }
                }
              }

              // Empty state
              Text {
                visible: !groupFlickable.activeGroup || !groupFlickable.activeGroup.items || groupFlickable.activeGroup.items.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Style.space(40)
                text: "No nodes available in this group"
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
              placeholderText: "Search host, outbound, or network..."
              Layout.fillWidth: true
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
            height: Style.space(330)
            contentWidth: width
            contentHeight: connsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: connsCol
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: {
                  if (!root.connectionsList) return []
                  if (!root.searchConnection) return root.connectionsList
                  var q = root.searchConnection.toLowerCase()
                  return root.connectionsList.filter(function(c) {
                    return (c.host && c.host.toLowerCase().indexOf(q) !== -1) ||
                           (c.destination && c.destination.toLowerCase().indexOf(q) !== -1) ||
                           (c.outbound && c.outbound.toLowerCase().indexOf(q) !== -1) ||
                           (c.network && c.network.toLowerCase().indexOf(q) !== -1)
                  })
                }

                BorderSurface {
                  width: parent.width
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                  radius: Style.cornerRadius
                  leftPadding: Style.space(10)
                  rightPadding: Style.space(10)
                  topPadding: Style.space(6)
                  bottomPadding: Style.space(6)

                  RowLayout {
                    anchors.fill: parent
                    spacing: Style.space(8)

                    ColumnLayout {
                      spacing: Style.space(2)
                      Layout.fillWidth: true

                      RowLayout {
                        spacing: Style.space(6)

                        // Network badge
                        BorderSurface {
                          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                          radius: Style.cornerRadius
                          leftPadding: Style.space(4)
                          rightPadding: Style.space(4)
                          topPadding: Style.space(1)
                          bottomPadding: Style.space(1)

                          Text {
                            anchors.centerIn: parent
                            text: modelData.network || "TCP"
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption * 0.85
                            font.bold: true
                            color: Color.accent
                          }
                        }

                        // Host / Destination
                        Text {
                          text: modelData.destination || modelData.host || "Unknown"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body * 0.95
                          font.bold: true
                          color: root.foreground
                          elide: Text.ElideMiddle
                          Layout.fillWidth: true
                        }
                      }

                      // Sub line: Outbound • Traffic
                      RowLayout {
                        spacing: Style.space(6)

                        Text {
                          text: "Via: " + (modelData.outbound || "direct")
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption * 0.9
                          color: root.dim
                        }

                        Text {
                          text: "•"
                          color: root.dim
                          font.pixelSize: Style.font.caption * 0.9
                        }

                        Text {
                          text: modelData.totalText ? modelData.totalText : ("↑ " + Model.formatBytes(modelData.upload) + "  ↓ " + Model.formatBytes(modelData.download))
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption * 0.9
                          color: root.foreground
                        }

                        Text {
                          visible: Boolean(modelData.rule)
                          text: "• " + modelData.rule
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption * 0.85
                          color: root.dim
                          elide: Text.ElideRight
                          Layout.fillWidth: true
                        }
                      }
                    }

                    // Close connection button
                    Button {
                      iconText: "󰅙"
                      tooltipText: "Close this connection"
                      onClicked: root.closeConn(modelData.id)
                    }
                  }
                }
              }

              // Empty Connections State
              Text {
                visible: !root.connectionsList || root.connectionsList.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Style.space(40)
                text: "No active connections tracked"
                font.family: root.fontFamily
                color: root.dim
              }
            }
          }
        }

        // -----------------------------------------------------------
        // TAB 4: LOGS
        // -----------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.currentTab === "logs"

          // Logs Level Filter & Refresh
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

            Button {
              iconText: "󰑐"
              tooltipText: "Reload service logs"
              iconSpinning: logsProc.running
              onClicked: root.fetchLogs()
            }
          }

          // Logs Console Surface
          BorderSurface {
            width: parent.width
            height: Style.space(340)
            color: "#161616"
            radius: Style.cornerRadius
            leftPadding: Style.space(8)
            rightPadding: Style.space(8)
            topPadding: Style.space(8)
            bottomPadding: Style.space(8)

            Flickable {
              anchors.fill: parent
              contentWidth: width
              contentHeight: logLinesCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: logLinesCol
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: root.logsList || []

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(6)

                    // Level Tag
                    BorderSurface {
                      color: {
                        var lvl = String(modelData.level || "").toLowerCase()
                        if (lvl === "error") return "#d32f2f"
                        if (lvl === "warn") return "#f57c00"
                        if (lvl === "debug") return "#7b1fa2"
                        if (lvl === "trace") return "#455a64"
                        return "#1976d2"
                      }
                      radius: Style.cornerRadius * 0.6
                      leftPadding: Style.space(4)
                      rightPadding: Style.space(4)
                      topPadding: 1
                      bottomPadding: 1

                      Text {
                        anchors.centerIn: parent
                        text: (modelData.level || "INFO").toUpperCase()
                        font.family: "Monospace"
                        font.pixelSize: Style.font.caption * 0.85
                        font.bold: true
                        color: "#ffffff"
                      }
                    }

                    // Log Message
                    Text {
                      text: modelData.message || ""
                      font.family: "Monospace"
                      font.pixelSize: Style.font.caption * 0.95
                      color: "#e0e0e0"
                      wrapMode: Text.WrapAnywhere
                      Layout.fillWidth: true
                    }
                  }
                }

                // Empty state for logs
                Text {
                  visible: !root.logsList || root.logsList.length === 0
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  topPadding: Style.space(40)
                  text: "No log entries found for level " + root.selectedLogLevel
                  font.family: "Monospace"
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
