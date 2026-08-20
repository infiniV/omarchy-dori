import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Dori: the attached Android phone's camera as a v4l2 webcam, and its screen
// mirrored here, both over adb.
//
// The panel owns no device logic. `bin/dori-status` reports the world as one
// JSON blob and the two action scripts change it; this only draws and
// dispatches. That keeps the whole thing usable from a terminal, and means a
// broken phone setup can be debugged without the shell in the way.
Panel {
  id: root
  moduleName: "io.github.infiniv.dori"
  ipcTarget: "dori"

  // ---------------------------------------------------------------- state
  property var status: ({})

  readonly property string deviceState: String(status.state || "absent")
  readonly property bool attached: deviceState !== "absent"
  readonly property bool ready: status.ready === true
  readonly property string model: String(status.model || "Phone")
  readonly property bool mirroring: status.mirroring === true
  readonly property bool recording: status.recording === true
  readonly property bool loopback: status.loopback !== false
  readonly property string card: String(status.card || "")
  readonly property string android: String(status.android || "")
  readonly property bool wireless: String(status.transport || "") === "wireless"
  readonly property bool relaying: status.relaying === true

  // Battery is only in the blob while the panel is open — it costs an adb round
  // trip, and the bar icon has nowhere to show it anyway.
  readonly property var battery: status.battery || null
  readonly property int batteryLevel: battery ? Number(battery.level) : -1
  readonly property bool charging: battery ? battery.charging === true : false

  // Which sensor is live. The ids are settings because "back is 0, front is 1"
  // holds on most phones and not on all of them.
  readonly property int cameraId:
    status.cameraId === undefined || status.cameraId === null ? -1 : Number(status.cameraId)
  readonly property string camera: {
    if (cameraId < 0) return "off"
    if (cameraId === backCameraId) return "back"
    if (cameraId === frontCameraId) return "front"
    return "cam" + cameraId
  }

  // Everything below lives in shell.json so it survives restarts, and is passed
  // to the scripts as flags rather than environment so the two always agree.
  readonly property string videoDevice: String(setting("videoDevice", "/dev/video10"))
  readonly property int backCameraId: Number(setting("backCameraId", 0))
  readonly property int frontCameraId: Number(setting("frontCameraId", 1))
  readonly property string frontRotation: String(setting("frontRotation", "0"))
  readonly property bool livePreview: setting("livePreview", true) === true
  readonly property string codec: setting("codec", "h264")
  readonly property int bitrate: Number(setting("bitrateMbps", 20))
  readonly property int maxFps: Number(setting("maxFps", 60))
  readonly property string keyboardMode: String(setting("keyboardMode", "sdk"))
  readonly property bool screenOff: setting("screenOff", false) === true

  // The live preview: a still frame of the phone's screen, refreshed while the
  // panel is open. Each grab writes to the other of two files so the image
  // loader is always handed a URL it has not cached.
  property string frameSlot: "a"
  property string framePath: ""
  // Which of the two image buffers is on screen. A frame is loaded into the
  // hidden one and only revealed once it is ready, so the preview never blinks
  // back to the placeholder between frames.
  property bool showA: true
  property real frameAspect: 0.46
  // dori-frame answers 2 when the phone's screen is off, which is not a failure
  // — it is the reason there is nothing new to show.
  property bool phoneScreenOff: false
  // Not while the mirror is up: the real window is right there, and polling the
  // phone for stills behind it would be work nobody asked for.
  readonly property bool previewVisible: livePreview && ready && !mirroring

  // The helper scripts ship inside the plugin folder, so the plugin works as
  // soon as it is cloned — nothing to copy onto PATH, nothing to keep in sync.
  readonly property string binDir: Qt.resolvedUrl("bin/").toString().replace(/^file:\/\//, "")
  function bin(name) { return binDir + name }

  // The widget stays on the bar with no phone attached, greyed out. Hiding it
  // is available but off by default: an icon that only exists once the cable
  // is in is indistinguishable from one that is broken, and there is nowhere
  // to look to find out which.
  readonly property bool hideWhenAbsent: setting("hideWhenAbsent", false) === true

  // A phone that is plugged in but not authorised is the single most common
  // failure, and it looks identical to "working" from the bar. Say it.
  readonly property string problem: {
    if (!attached) return "No phone detected — connect it by USB with debugging enabled"
    if (deviceState === "unauthorized") return "Accept the USB debugging prompt on the phone"
    if (deviceState === "offline") return "Phone is offline — replug the cable"
    if (!ready) return "Phone is " + deviceState
    if (!loopback) return "No webcam device at " + videoDevice + " — run bin/dori-setup once"
    return ""
  }

  readonly property string heroStatus: {
    if (!attached) return "Not connected"
    if (problem !== "") return deviceState.toUpperCase()
    if (recording) return "Recording the screen"
    if (mirroring && camera !== "off") return "Mirroring · " + camera + " camera"
    if (mirroring) return "Mirroring screen"
    if (camera !== "off") return camera.toUpperCase() + " CAMERA LIVE"
    if (wireless) return "Connected over Wi-Fi"
    return "Connected over USB"
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Nerd Font: cellphone-link. Lit when anything is actively streaming.
  readonly property string phoneGlyph: "󰄜"
  readonly property bool streaming: camera !== "off" || mirroring || recording

  // ------------------------------------------------------------- actions
  function refresh() {
    if (statusProc.running) return
    var command = [bin("dori-status"), "--device", videoDevice]
    if (opened) command.push("--full")
    statusProc.command = command
    statusProc.running = true
  }

  function runAction(command) {
    if (actionProc.running) return
    actionProc.command = command
    actionProc.running = true
  }

  function setCamera(target) {
    if (!ready && target !== "off") return
    runAction([bin("dori-camera"), target,
               "--device", videoDevice,
               "--back-id", String(backCameraId),
               "--front-id", String(frontCameraId),
               "--front-rotation", frontRotation])
  }

  // `screenOff` is an optional override: the blank-screen toggle needs to build
  // the restart command from the value it just wrote, not from a binding that
  // may not have settled yet.
  function mirrorArgs(action, screenOff) {
    var off = screenOff === undefined ? root.screenOff : screenOff
    var args = [bin("dori-mirror"), action,
                "--codec", root.codec,
                "--bitrate", root.bitrate + "M",
                "--fps", String(root.maxFps),
                "--keyboard", root.keyboardMode]
    args.push(off ? "--screen-off" : "--no-screen-off")
    return args
  }

  function grabFrame() {
    if (frameProc.running || !ready || !livePreview || mirroring) return
    frameSlot = frameSlot === "a" ? "b" : "a"
    frameProc.command = [bin("dori-frame"), "--slot", frameSlot, "--width", "260"]
    frameProc.running = true
  }

  function screenshot() {
    if (ready) runAction([bin("dori-shot")])
  }

  function toggleRecording() {
    if (!ready && !recording) return
    runAction([bin("dori-record"), "toggle",
               "--codec", root.codec,
               "--bitrate", root.bitrate + "M"])
  }

  // Switching to Wi-Fi needs the cable in once; switching back only needs the
  // network connection we already have.
  function toggleWireless() {
    runAction([bin("dori-wireless"), wireless ? "off" : "on"])
  }

  function toggleRelay() {
    runAction([bin("dori-notify"), "toggle"])
  }

  function updateSetting(key, value) {
    var next = {}
    for (var k in root.settings) next[k] = root.settings[k]
    next[key] = value
    root.settings = next
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, next)
  }

  // ------------------------------------------------------------ lifecycle
  visible: attached || !hideWhenAbsent
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  // Only close on disconnect if the widget is about to vanish anyway —
  // otherwise the panel stays up and says what happened.
  onAttachedChanged: if (!attached && hideWhenAbsent) close()
  onOpenedChanged: if (opened) refresh()
  Component.onCompleted: refresh()

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || ""))
          root.status = parsed && typeof parsed === "object" ? parsed : ({})
        } catch (e) {
          root.status = ({})
        }
      }
    }
  }

  // A frame that fails — phone mid-unlock, screen rotating — leaves the last
  // good one on screen rather than blanking the preview.
  Process {
    id: frameProc
    onExited: function(code) { root.phoneScreenOff = code === 2 }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path === "") return
        root.framePath = "file://" + path
        if (root.showA) frameB.source = root.framePath
        else frameA.source = root.framePath
      }
    }
  }

  // One frame every two and a half seconds, only while the panel is open. A
  // grab costs about a second of adb, so this is a slideshow on purpose.
  Timer {
    // Over Wi-Fi a frame costs more and the link is shared with everything else
    // Dori is doing, so ask for fewer of them.
    interval: root.wireless ? 4000 : 2500
    running: root.opened && root.previewVisible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.grabFrame()
  }

  Process {
    id: actionProc
    onExited: settleTimer.restart()
  }

  // scrcpy needs a beat to claim the sink, raise its window, or open the
  // recording file before the next status read tells the truth about it.
  Timer {
    id: settleTimer
    interval: 700
    onTriggered: root.refresh()
  }

  // Poll fast while the panel is open, slowly otherwise — the bar icon only
  // needs to notice a cable going in or out.
  Timer {
    interval: root.opened ? 2000 : 6000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.phoneGlyph
    // Dimmed until something is actually streaming, so the icon carries state
    // rather than just presence.
    foreground: root.streaming
      ? (root.bar ? root.bar.barForeground : Color.foreground)
      : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.55)
    tooltipText: root.attached
      ? root.model + (root.problem !== "" ? " — " + root.problem : "")
      : "Phone — " + root.problem
    onPressed: function(b) {
      if (b === Qt.RightButton) root.setCamera("cycle")
      else if (b === Qt.MiddleButton) root.runAction(root.mirrorArgs("toggle"))
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360) + body.previewSpace)
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Row {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // The preview is as tall as the controls beside it and as wide as that
        // height allows at the phone's own aspect ratio, so it reads as a phone
        // rather than as a picture of one.
        readonly property real previewWidth:
          Math.max(Style.space(140),
                   Math.min(Style.space(300),
                            Math.round(column.implicitHeight * root.frameAspect)))
        readonly property real previewSpace:
          root.previewVisible ? previewWidth + spacing : 0

        Rectangle {
          id: previewPane
          visible: root.previewVisible
          width: root.previewVisible ? body.previewWidth : 0
          height: column.implicitHeight
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
          clip: true

          Image {
            id: frameA
            anchors.fill: parent
            anchors.margins: Style.space(4)
            fillMode: Image.PreserveAspectFit
            cache: false
            asynchronous: true
            smooth: true
            opacity: root.showA ? 1 : 0
            onStatusChanged: if (status === Image.Ready) {
              root.frameAspect = implicitWidth / implicitHeight
              root.showA = true
            }
            Behavior on opacity { NumberAnimation { duration: 160 } }
          }

          Image {
            id: frameB
            anchors.fill: parent
            anchors.margins: Style.space(4)
            fillMode: Image.PreserveAspectFit
            cache: false
            asynchronous: true
            smooth: true
            opacity: root.showA ? 0 : 1
            onStatusChanged: if (status === Image.Ready) {
              root.frameAspect = implicitWidth / implicitHeight
              root.showA = false
            }
            Behavior on opacity { NumberAnimation { duration: 160 } }
          }

          // Only until the first frame lands. After that the last good frame
          // stays up, which is more honest than a blinking icon.
          Text {
            anchors.centerIn: parent
            visible: frameA.status !== Image.Ready && frameB.status !== Image.Ready
                     && !root.phoneScreenOff
            text: root.phoneGlyph
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          // A dark phone and a stale picture of a bright one look the same.
          // Say which it is instead.
          Rectangle {
            anchors.fill: parent
            visible: root.phoneScreenOff
            color: Qt.rgba(0, 0, 0, 0.72)
            radius: parent.radius

            Column {
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰤄"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Screen off"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }
          }
        }

      Column {
        id: column
        width: parent.width - body.previewSpace
        spacing: Style.space(14)

        // ------------------------------------------------------- hero
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: root.phoneGlyph
            color: root.streaming ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          // Battery, when the phone is attached and the panel is open. It sits
          // in the hero rather than a row of its own: it is context, not a
          // control, and it is the first thing you look for before starting a
          // long mirror session.
          Row {
            id: heroBattery
            visible: root.batteryLevel >= 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              text: root.charging ? "󰂄" : "󰁹"
              color: root.charging ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.batteryLevel + "%"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroBattery.visible ? heroBattery.left : parent.right
            anchors.rightMargin: heroBattery.visible ? Style.space(10) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.android !== "" ? root.model + "  ·  Android " + root.android : root.model
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.heroStatus.toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ------------------------------------------- problem callout
        // Only drawn when something is actually wrong, so the panel is not
        // permanently carrying a warning slot.
        Rectangle {
          visible: root.problem !== ""
          width: parent.width
          implicitHeight: problemText.implicitHeight + Style.space(18)
          radius: Style.cornerRadius
          color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.12)

          Text {
            id: problemText
            anchors.fill: parent
            anchors.margins: Style.space(9)
            text: root.problem
            color: root.urgentColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
          }
        }

        // -------------------------------------------------- camera
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "CAMERA"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: cameraRow
            width: parent.width
            spacing: Style.space(6)

            readonly property var choices: [
              { value: "off", label: "Off", icon: "󰗟" },
              { value: "back", label: "Back", icon: "󰄀" },
              { value: "front", label: "Front", icon: "󰄂" }
            ]
            readonly property real cellWidth: (width - spacing * 2) / 3

            Repeater {
              model: cameraRow.choices

              Button {
                required property var modelData
                width: cameraRow.cellWidth
                iconText: modelData.icon
                iconSize: Style.font.title
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.camera === modelData.value
                // "Off" always works — it is how you free a stuck sink. The
                // live cameras need a phone that adb will actually talk to.
                enabled: modelData.value === "off" || (root.ready && root.loopback)
                opacity: enabled ? 1 : 0.4
                onClicked: root.setCamera(modelData.value)
              }
            }
          }

          InfoPair {
            label: root.card !== "" ? root.card : "Webcam device"
            value: root.loopback ? root.videoDevice : "not loaded"
          }
        }

        // -------------------------------------------------- screen
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "SCREEN"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: mirrorRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * 2) / 3

            Button {
              width: mirrorRow.cellWidth
              iconText: "󰍹"
              iconSize: Style.font.title
              text: "Mirror"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: root.mirroring
              enabled: root.ready && !root.mirroring
              opacity: enabled ? 1 : 0.4
              onClicked: root.runAction(root.mirrorArgs("start"))
            }

            Button {
              width: mirrorRow.cellWidth
              iconText: "󰏋"
              iconSize: Style.font.title
              text: "Focus"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              enabled: root.mirroring
              opacity: enabled ? 1 : 0.4
              onClicked: root.runAction([root.bin("dori-mirror"), "focus"])
            }

            Button {
              width: mirrorRow.cellWidth
              iconText: "󰓛"
              iconSize: Style.font.title
              text: "Stop"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              enabled: root.mirroring
              opacity: enabled ? 1 : 0.4
              onClicked: root.runAction([root.bin("dori-mirror"), "stop"])
            }
          }

          // Two things you want without a window in the way: a screenshot that
          // lands on the clipboard, and a recording that keeps going while you
          // use the phone normally.
          Row {
            id: captureRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: captureRow.cellWidth
              iconText: "󰹑"
              iconSize: Style.font.title
              text: "Screenshot"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              enabled: root.ready
              opacity: enabled ? 1 : 0.4
              onClicked: root.screenshot()
            }

            Button {
              width: captureRow.cellWidth
              iconText: root.recording ? "󰓛" : "󰑊"
              iconSize: Style.font.title
              text: root.recording ? "Stop recording" : "Record"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: root.recording
              enabled: root.ready || root.recording
              opacity: enabled ? 1 : 0.4
              onClicked: root.toggleRecording()
            }
          }

          // Codec. Changing it while mirroring would not take effect until the
          // next start, so the row is locked during a session rather than
          // quietly lying about what is on screen.
          Row {
            width: parent.width
            spacing: Style.space(8)

            InfoLabel {
              text: "Codec"
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(70)
            }

            ButtonGroup {
              width: parent.width - Style.space(78)
              options: [
                { value: "h264", label: "h264" },
                { value: "h265", label: "h265" }
              ]
              value: root.codec
              foreground: root.foreground
              enabled: !root.mirroring
              opacity: enabled ? 1 : 0.4
              onChanged: function(next) { root.updateSetting("codec", next) }
            }
          }

          // Bitrate, in whole Mbps. 4 is unwatchable and 60 saturates USB 2;
          // the range is what is actually useful between those.
          Row {
            width: parent.width
            spacing: Style.space(8)

            InfoLabel {
              text: "Bitrate"
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(70)
            }

            PanelSlider {
              id: bitrateSlider
              bar: root.bar
              width: parent.width - Style.space(78) - bitrateValue.width - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              minimum: 4
              maximum: 60
              step: 2
              integer: true
              value: root.bitrate
              enabled: !root.mirroring
              opacity: enabled ? 1 : 0.4
              onReleased: function(v) { root.updateSetting("bitrateMbps", Math.round(v)) }
            }

            InfoValue {
              id: bitrateValue
              text: Math.round(bitrateSlider.liveValue) + "M"
              width: Style.space(34)
              horizontalAlignment: Text.AlignRight
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // scrcpy only reads --turn-screen-off when it launches, so flipping
          // this during a session used to save the setting and change nothing
          // on the phone — a switch that moves and does nothing. Restart the
          // mirror instead, and say so in the description.
          Toggle {
            width: parent.width
            label: "Blank phone screen"
            description: root.mirroring
              ? "Turn the phone's own display off — restarts the mirror"
              : "Turn the phone's own display off while mirroring"
            checked: root.screenOff
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              var next = !root.screenOff
              root.updateSetting("screenOff", next)
              if (root.mirroring) root.runAction(root.mirrorArgs("restart", next))
            }
          }
        }

        // -------------------------------------------- connection
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "CONNECTION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // adb over Wi-Fi. Turning it on needs the cable in once, so the row
          // is only live when there is something to switch over — otherwise it
          // is a switch that moves and does nothing.
          Toggle {
            width: parent.width
            label: root.wireless ? "Connected over Wi-Fi" : "Work without the cable"
            description: root.wireless
              ? "The cable can come out — " + root.model + " stays reachable"
              : (root.ready
                 ? "Switch this phone to Wi-Fi, then unplug it"
                 : "Plug the phone in once to switch it to Wi-Fi")
            checked: root.wireless
            enabled: root.ready || root.wireless
            opacity: enabled ? 1 : 0.4
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleWireless()
          }

          // The phone's notifications, read straight off adb and handed to the
          // desktop. No app on the phone, no account in the middle.
          Toggle {
            width: parent.width
            label: "Relay notifications"
            description: root.relaying
              ? "The phone's notifications arrive here"
              : "Show the phone's notifications on this desktop"
            checked: root.relaying
            enabled: root.ready || root.relaying
            opacity: enabled ? 1 : 0.4
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleRelay()
          }
        }
      }
      }
    }
  }

  readonly property color urgentColor: bar ? bar.urgent : Color.urgent

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: parent.label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: parent.value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
