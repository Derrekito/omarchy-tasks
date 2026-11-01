import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Tasks: a bar icon that opens a checklist popup. All reads and writes go
// through bin/tasks (the same CLI agents use), so there is exactly one writer
// path and it holds a lock. The FileView only watches the JSON for changes so
// agent-added tasks appear live.
Panel {
  id: root
  moduleName: "derrekito.tasks"
  ipcTarget: "derrekito.tasks"

  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/tasks")).replace(/^file:\/\//, ""))
  property var tasks: []
  property string dataPath: ""
  readonly property int openCount: {
    var n = 0
    for (var i = 0; i < tasks.length; i++) if (!tasks[i].done) n++
    return n
  }
  readonly property int doneCount: tasks.length - openCount

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // One process prints the data path then the list, so a switch between
  // persistent and ephemeral mode is picked up on the next refresh.
  function refresh() {
    if (listProc.running) { listQueued = true; return }
    listProc.running = true
  }
  property bool listQueued: false

  function run(args) {
    Quickshell.execDetached([root.cli].concat(args))
  }

  function addFromInput() {
    var t = input.text.trim()
    if (t === "") { input.forceActiveFocus(); return }
    run(["add", "--by", "human", t])
    input.text = ""
    input.forceActiveFocus()
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) { refresh(); Qt.callLater(function() { input.forceActiveFocus() }) }

  Process {
    id: listProc
    command: ["sh", "-c", "\"$0\" path && \"$0\" ls --json", root.cli]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text)
        var nl = out.indexOf("\n")
        if (nl < 0) return
        var path = out.slice(0, nl).trim()
        if (path !== "" && path !== root.dataPath) root.dataPath = path
        try {
          var parsed = JSON.parse(out.slice(nl + 1))
          if (Array.isArray(parsed)) root.tasks = parsed
        } catch (e) { /* keep last good list */ }
      }
    }
    onExited: if (root.listQueued) { root.listQueued = false; Qt.callLater(root.refresh) }
  }

  FileView {
    path: root.dataPath
    watchChanges: root.dataPath !== ""
    printErrors: false
    onFileChanged: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-format_list_checkbox; open count beside it when there is work left
    text: root.openCount > 0 && !vertical ? "\u{F096A} " + root.openCount : "\u{F096A}"
    slotSize: Style.bar.iconSlot * (root.openCount > 0 && !vertical ? 1.6 : 1)
    tooltipText: root.openCount > 0 ? root.openCount + " open task" + (root.openCount === 1 ? "" : "s") : "Tasks"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: input
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: input.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: "\u{F096A}"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Tasks"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: (root.tasks.length === 0 ? "NOTHING TO DO"
                     : root.openCount + " OPEN · " + root.doneCount + " DONE")
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        // ---------- Add row ----------
        Row {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: input
            width: parent.width - addButton.width - parent.spacing
            placeholderText: "New task…"
            foreground: root.bar.foreground
            onAccepted: root.addFromInput()
            Keys.onEscapePressed: root.close()
          }

          Button {
            id: addButton
            iconText: "\u{F0415}" // nf-md-plus
            iconSize: Style.font.title
            tooltipText: "Add task"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            height: input.height
            onClicked: root.addFromInput()
          }
        }

        PanelSeparator { foreground: root.bar.foreground; visible: root.tasks.length > 0 }

        // ---------- List ----------
        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(360))
          visible: root.tasks.length > 0
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          model: root.tasks

          delegate: Item {
            id: row
            required property var modelData
            width: list.width
            height: Math.max(check.implicitHeight, label.implicitHeight) + Style.space(10)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, rowMouse.containsMouse ? 0.08 : 0)
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.run(["toggle", String(row.modelData.id)])
            }

            Text {
              id: check
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              // nf-md-checkbox_marked / checkbox_blank_outline
              text: row.modelData.done ? "\u{F0132}" : "\u{F0131}"
              color: root.bar.foreground
              opacity: row.modelData.done ? 0.5 : 1
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              id: label
              anchors.left: check.right
              anchors.leftMargin: Style.space(10)
              anchors.right: removeBtn.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: row.modelData.text + (row.modelData.by && row.modelData.by !== "human" ? "  · " + row.modelData.by : "")
              color: root.bar.foreground
              opacity: row.modelData.done ? 0.45 : 1
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.strikeout: row.modelData.done
            }

            Text {
              id: removeBtn
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "\u{F0156}" // nf-md-close
              color: root.bar.foreground
              opacity: rowMouse.containsMouse || removeMouse.containsMouse ? (removeMouse.containsMouse ? 1 : 0.5) : 0
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body

              MouseArea {
                id: removeMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.run(["rm", String(row.modelData.id)])
              }
            }
          }
        }

        // ---------- Footer ----------
        Button {
          visible: root.doneCount > 0
          width: parent.width
          text: "Clear " + root.doneCount + " completed"
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          onClicked: root.run(["clear"])
        }
      }
    }
  }
}
