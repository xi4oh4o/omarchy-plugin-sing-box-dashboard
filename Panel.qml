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

  property bool settingsOpen: parentWidget ? (!parentWidget.online) : true
  property string inputUrl: parentWidget ? parentWidget.effectiveUrl : "http://127.0.0.1:9090"
  property string inputPassword: parentWidget ? parentWidget.effectivePassword : ""
  property bool showPassword: false
  property string actionMessage: ""

  function open() {
    if (parentWidget) {
      inputUrl = parentWidget.effectiveUrl
      inputPassword = parentWidget.effectivePassword
      settingsOpen = !parentWidget.online
      parentWidget.refreshNow()
    }
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

  function saveConfig(newUrl, newPass) {
    saveProc.command = ["python3", root.scriptPath, "save-config", newUrl, newPass]
    saveProc.running = true
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

  function testDelay(nodeName) {
    if (!parentWidget) return
    actionProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "urltest", nodeName]
    actionProc.running = true
  }

  function closeAllConnections() {
    if (!parentWidget) return
    actionProc.command = ["python3", root.scriptPath, "--url", parentWidget.effectiveUrl, "--password", parentWidget.effectivePassword, "close-connections"]
    actionProc.running = true
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
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

        // Header
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "󰒋"
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            color: root.parentWidget && root.parentWidget.online ? "#4caf50" : (root.parentWidget && root.parentWidget.httpStatus === 401 ? "#ff9800" : "#f44336")
          }

          Text {
            text: "sing-box"
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            color: root.foreground
            Layout.fillWidth: true
          }

          // Status Badge
          BorderSurface {
            id: statusBadge
            property color badgeColor: root.parentWidget && root.parentWidget.online ? "#4caf50" : (root.parentWidget && root.parentWidget.httpStatus === 401 ? "#ff9800" : "#f44336")
            color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.15)
            radius: Style.cornerRadius
            leftPadding: Style.space(6)
            rightPadding: Style.space(6)
            topPadding: Style.space(2)
            bottomPadding: Style.space(2)

            Text {
              anchors.centerIn: parent
              text: root.parentWidget && root.parentWidget.online ? ("Online (" + root.parentWidget.apiType + ")") : (root.parentWidget && root.parentWidget.httpStatus === 401 ? "Unauthorized" : "Offline")
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: statusBadge.badgeColor
            }
          }

          // Settings toggle
          Button {
            iconText: "󰒓"
            tooltipText: "Configure API"
            selected: root.settingsOpen
            onClicked: root.settingsOpen = !root.settingsOpen
          }

          // Refresh button
          Button {
            iconText: "󰑐"
            tooltipText: "Refresh"
            onClicked: if (root.parentWidget) root.parentWidget.refreshNow()
          }
        }

        // Mode switch pills (Rule / Global / Direct)
        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          Button {
            text: "Rule"
            Layout.fillWidth: true
            selected: root.parentWidget && root.parentWidget.currentMode === "Rule"
            onClicked: root.setMode("Rule")
          }

          Button {
            text: "Global"
            Layout.fillWidth: true
            selected: root.parentWidget && root.parentWidget.currentMode === "Global"
            onClicked: root.setMode("Global")
          }

          Button {
            text: "Direct"
            Layout.fillWidth: true
            selected: root.parentWidget && root.parentWidget.currentMode === "Direct"
            onClicked: root.setMode("Direct")
          }
        }

        PanelSeparator { width: parent.width }

        // Settings section
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.settingsOpen

          Text {
            text: "API Configuration"
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            color: root.foreground
          }

          Text {
            text: "HTTP URL"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.dim
          }

          TextField {
            id: urlField
            width: parent.width
            text: root.inputUrl
            placeholderText: "http://127.0.0.1:9090"
            onTextChanged: root.inputUrl = text
          }

          Text {
            text: "Password / Secret"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.dim
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: passField
              Layout.fillWidth: true
              text: root.inputPassword
              password: !root.showPassword
              placeholderText: "Secret / Bearer token (optional)"
              onTextChanged: root.inputPassword = text
            }

            Button {
              iconText: root.showPassword ? "󰈈" : "󰈉"
              tooltipText: root.showPassword ? "Hide password" : "Show password"
              onClicked: root.showPassword = !root.showPassword
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Save & Connect"
              iconText: "󰄬"
              bordered: true
              Layout.fillWidth: true
              onClicked: root.saveConfig(root.inputUrl, root.inputPassword)
            }
          }

          Text {
            width: parent.width
            text: root.parentWidget && root.parentWidget.httpStatus === 401
              ? "⚠️ API returned 401 Unauthorized. Please enter the password/secret configured in sing-box."
              : "Supports Clash API (e.g. http://127.0.0.1:9090) or daemon API (e.g. http://127.0.0.1:9091)."
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            color: root.parentWidget && root.parentWidget.httpStatus === 401 ? "#ff9800" : root.dim
          }

          PanelSeparator { width: parent.width }
        }

        // Live Traffic Metrics (when online)
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.parentWidget && root.parentWidget.online

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            // Upload Card
            BorderSurface {
              Layout.fillWidth: true
              color: Style.cardFill(false, false, root.foreground, Color.accent)
              radius: Style.cornerRadius
              padding: Style.space(8)

              Column {
                spacing: Style.space(2)
                Text {
                  text: "󰕒 Upload"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
                Text {
                  text: Model.formatRate(root.parentWidget ? root.parentWidget.uploadRate : 0)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: root.foreground
                }
                Text {
                  text: "Total: " + Model.formatBytes(root.parentWidget ? root.parentWidget.uploadTotal : 0)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }
            }

            // Download Card
            BorderSurface {
              Layout.fillWidth: true
              color: Style.cardFill(false, false, root.foreground, Color.accent)
              radius: Style.cornerRadius
              padding: Style.space(8)

              Column {
                spacing: Style.space(2)
                Text {
                  text: "󰇚 Download"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
                Text {
                  text: Model.formatRate(root.parentWidget ? root.parentWidget.downloadRate : 0)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: root.foreground
                }
                Text {
                  text: "Total: " + Model.formatBytes(root.parentWidget ? root.parentWidget.downloadTotal : 0)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }
            }
          }
        }

        // Outbound Groups & Proxies
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.parentWidget && root.parentWidget.online && root.parentWidget.groupsData && root.parentWidget.groupsData.length > 0

          Text {
            text: "Outbound Groups"
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            color: root.foreground
          }

          Repeater {
            model: root.parentWidget ? root.parentWidget.groupsData : []

            delegate: Column {
              id: groupCol
              width: contentCol.width
              spacing: Style.space(4)
              property var groupObj: modelData

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  text: "󰇧 " + (groupObj.name || "")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: root.foreground
                  Layout.fillWidth: true
                }

                Button {
                  text: "Test"
                  iconText: "󰓅"
                  fontSize: Style.font.caption
                  onClicked: root.testDelay(groupObj.name)
                }
              }

              // Nodes flow / list
              Flow {
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: groupObj.items || []

                  delegate: Button {
                    property var nodeObj: modelData
                    property bool isSelected: nodeObj.name === groupObj.selected
                    text: (isSelected ? "󰄬 " : "") + (nodeObj.name || "") + (nodeObj.delay > 0 ? (" (" + nodeObj.delay + "ms)") : "")
                    selected: isSelected
                    fontSize: Style.font.caption
                    onClicked: root.selectNode(groupObj.name, nodeObj.name)
                  }
                }
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        // Bottom Actions
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Close Connections"
            iconText: "󰅙"
            Layout.fillWidth: true
            onClicked: root.closeAllConnections()
          }

          Button {
            text: "Dashboard"
            iconText: "󰆏"
            Layout.fillWidth: true
            onClicked: root.openDashboard()
          }
        }
      }
    }
  }
}
