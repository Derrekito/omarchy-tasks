import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Tasks: a bar icon that opens a checklist (or kanban board) popup. All reads
// and writes go through bin/tasks (the same CLI agents use), so there is
// exactly one writer path and it holds a lock. The FileView only watches the
// JSON for changes so agent-made changes appear live.
Panel {
  id: root
  moduleName: "derrekito.tasks"
  ipcTarget: "derrekito.tasks"

  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/tasks")).replace(/^file:\/\//, ""))
  property var tasks: []
  property string dataPath: ""
  property string view: "list"          // "list" | "kanban", from `tasks config view`
  readonly property bool kanban: view === "kanban"

  readonly property var todoTasks: tasks.filter(function(t) { return t.status === "todo" })
  readonly property var doingTasks: tasks.filter(function(t) { return t.status === "doing" })
  readonly property var doneTasks: tasks.filter(function(t) { return t.status === "done" })
  readonly property int openCount: todoTasks.length + doingTasks.length
  readonly property int doneCount: doneTasks.length

  readonly property string glyphTodo: "\u{F0131}"   // nf-md-checkbox_blank_outline
  readonly property string glyphDoing: "\u{F0856}"  // nf-md-checkbox_intermediate
  readonly property string glyphDone: "\u{F0132}"   // nf-md-checkbox_marked
  function glyphFor(status) { return status === "done" ? glyphDone : (status === "doing" ? glyphDoing : glyphTodo) }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // One process prints the data path, the view, then the list, so config
  // switches (ephemeral, view) are picked up on the next refresh.
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

  function metaFor(task) {
    var parts = []
    if (task.by && task.by !== "human") parts.push(task.by)
    if (task.status === "doing") {
      // who claimed it matters when it's an agent; the kanban column already says "doing"
      var claimer = task.startedBy && task.startedBy !== "human" ? task.startedBy : ""
      if (claimer === task.by) parts = []   // don't name the same agent twice
      if (claimer) parts.push("doing: " + claimer)
      else if (!kanban) parts.push("doing")
    }
    return parts.join(" · ")
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) { refresh(); Qt.callLater(function() { input.forceActiveFocus() }) }

  Process {
    id: listProc
    command: [root.cli, "_widget"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text)
        var nl1 = out.indexOf("\n")
        var nl2 = nl1 < 0 ? -1 : out.indexOf("\n", nl1 + 1)
        if (nl2 < 0) return
        var path = out.slice(0, nl1).trim()
        var v = out.slice(nl1 + 1, nl2).trim()
        if (path !== "" && path !== root.dataPath) root.dataPath = path
        root.view = v === "kanban" ? "kanban" : "list"
        try {
          var parsed = JSON.parse(out.slice(nl2 + 1))
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
    contentWidth: panel.fittedContentWidth(Style.space(root.kanban ? 760 : 380))
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
              text: root.tasks.length === 0 ? "NOTHING TO DO"
                : (root.doingTasks.length > 0
                   ? root.todoTasks.length + " TODO · " + root.doingTasks.length + " DOING · " + root.doneCount + " DONE"
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

        PanelSeparator { foreground: root.bar.foreground; visible: root.tasks.length > 0 || root.kanban }

        // ---------- List view ----------
        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(360))
          visible: !root.kanban && root.tasks.length > 0
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          model: root.kanban ? [] : root.tasks

          delegate: TaskItem {
            required property var modelData
            task: modelData
            width: list.width
            // list view: click toggles done <-> todo (a doing task completes)
            onActivated: root.run(["toggle", String(modelData.id)])
            onSecondary: root.run(["prev", String(modelData.id)])
          }
        }

        // ---------- Kanban view ----------
        Row {
          id: board
          visible: root.kanban
          width: parent.width
          spacing: Style.space(10)
          readonly property real colWidth: (width - spacing * 2) / 3

          Repeater {
            model: root.kanban ? [
              { key: "todo", title: "TODO", items: root.todoTasks },
              { key: "doing", title: "DOING", items: root.doingTasks },
              { key: "done", title: "DONE", items: root.doneTasks }
            ] : []

            Column {
              id: lane
              required property var modelData
              width: board.colWidth
              spacing: Style.space(6)

              Row {
                spacing: Style.space(6)
                Text {
                  text: root.glyphFor(lane.modelData.key)
                  color: root.bar.foreground
                  opacity: 0.6
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: lane.modelData.title + "  " + lane.modelData.items.length
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }
              }

              Rectangle {
                width: parent.width
                height: Math.max(laneList.height + Style.space(8), Style.space(48))
                radius: Style.cornerRadius
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.04)

                Text {
                  anchors.centerIn: parent
                  visible: lane.modelData.items.length === 0
                  text: "empty"
                  color: root.bar.foreground
                  opacity: 0.3
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                ListView {
                  id: laneList
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(4)
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width - Style.space(8)
                  height: Math.min(contentHeight, Style.space(400))
                  clip: true
                  spacing: Style.space(4)
                  boundsBehavior: Flickable.StopAtBounds
                  model: lane.modelData.items

                  delegate: TaskItem {
                    required property var modelData
                    task: modelData
                    card: true
                    width: laneList.width
                    // kanban: click moves right, right-click moves left
                    onActivated: root.run(["next", String(modelData.id)])
                    onSecondary: root.run(["prev", String(modelData.id)])
                  }
                }
              }
            }
          }
        }

        Text {
          visible: root.kanban && root.tasks.length > 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Click a card to move it right, right-click to move it back"
          color: root.bar.foreground
          opacity: 0.4
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
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

  // One task: a checklist row (list view) or a bordered card (kanban).
  component TaskItem: Item {
    id: item
    property var task: ({})
    property bool card: false
    signal activated()
    signal secondary()

    readonly property bool isDone: task.status === "done"
    readonly property string meta: root.metaFor(task)
    readonly property real pad: Style.space(card ? 8 : 5)

    height: Math.max(check.implicitHeight, textCol.implicitHeight) + pad * 2

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b,
                     itemMouse.containsMouse ? 0.10 : (item.card ? 0.05 : 0))
      border.width: item.card ? 1 : 0
      border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.15)
    }

    MouseArea {
      id: itemMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) item.secondary()
        else item.activated()
      }
    }

    Text {
      id: check
      visible: !item.card
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyphFor(item.task.status)
      color: root.bar.foreground
      opacity: item.isDone ? 0.5 : 1
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title
    }

    Column {
      id: textCol
      anchors.left: item.card ? parent.left : check.right
      anchors.leftMargin: item.card ? Style.space(10) : Style.space(10)
      anchors.right: removeBtn.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: item.card || item.meta === "" ? String(item.task.text || "") : item.task.text + "  · " + item.meta
        color: root.bar.foreground
        opacity: item.isDone ? 0.45 : 1
        font.family: root.bar.fontFamily
        font.pixelSize: item.card ? Style.font.bodySmall : Style.font.body
        font.strikeout: item.isDone
      }

      Text {
        visible: item.card && item.meta !== ""
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: item.meta
        color: root.bar.foreground
        opacity: 0.5
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      id: removeBtn
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: "\u{F0156}" // nf-md-close
      color: root.bar.foreground
      opacity: itemMouse.containsMouse || removeMouse.containsMouse ? (removeMouse.containsMouse ? 1 : 0.5) : 0
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body

      MouseArea {
        id: removeMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.run(["rm", String(item.task.id)])
      }
    }
  }
}
