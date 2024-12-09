import QtQuick 2.0
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.5
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.All

    property string guildid
    property string channelid
    property string name
    property bool isDemo: false
    property bool sendPermissions: true
    property bool isDM: false
    property string userid: ''
    property string usericon: ''

    Timer {
        id: activeFocusTimer
        interval: 100
        onTriggered: sendField.forceActiveFocus()
    }

    function sendMessage() {
        if (!isDemo) python.sendMessage(sendField.text)
        else msgModel.appendDemo(true, sendField.text)
        sendField.text = ""
        if (appSettings.focusAfterSend) activeFocusTimer.start()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: height

        BusyLabel {
            running: msgModel.count === 0 && waitForMessagesTimer.running
        }

        ViewPlaceholder {
            enabled: msgModel.count === 0 && !waitForMessagesTimer.running
            text: qsTr("No messages")
            hintText: qsTr("Say hi ;)")

            Timer {
                id: waitForMessagesTimer
                interval: 2500
                running: true
            }
        }

        Column {
            id: column
            width: parent.width
            height: parent.height - (isDM ? Theme.paddingLarge : 0)

            PageHeader {
                id: header
                title: (isDM ? '@' : "#")+name
            }

            Item {
                width: parent.width
                height: parent.height - header.height - (sendField.visible ? sendField.height : 0)

                SilicaListView {
                    id: messagesList
                    anchors.fill: parent
                    model: msgModel
                    clip: true
                    verticalLayoutDirection: ListView.BottomToTop

                    VerticalScrollDecorator {}

                    function getVisibleIndexRange() { // this one actually works!
                        var center_x = messagesList.x + messagesList.width / 2
                        return [indexAt( center_x, messagesList.y + messagesList.contentY + 10),
                                indexAt( center_x, messagesList.y + messagesList.contentY + messagesList.height - 10)]
                    }

                    function checkForUpdate() {
                        var rng = getVisibleIndexRange()
                        for (var i=rng[1]; i<=rng[0]; i++) {
                            if (i>0 && i%27 == 0) {
                                if (!msgModel.get(i)._wasUpdated) {
                                    msgModel.get(i)._wasUpdated = true
                                    python.requestOlderHistory(msgModel.get(msgModel.count-1).messageId)
                                }
                            }
                        }
                    }

                    onContentYChanged: checkForUpdate()

                    delegate: Loader {
                        width: parent.width
                        sourceComponent:
                            switch (type) {
                            case '': return defaultItem
                            case 'unknown': return appSettings.defaultUnknownMessages ? defaultItem : systemItem
                            default: return systemItem
                            }

                        Rectangle {
                            anchors.fill: parent
                            visible: appSettings.highContrastMessages && parent.status == Loader.Ready
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightBackgroundColor, 0) }
                                GradientStop { position: 1.0; color: Theme.rgba(Theme.secondaryColor, 0.1) }
                            }
                        }

                        Component {
                            id: defaultItem
                            MessageItem {
                                authorid: userid
                                contents: _contents
                                author: _author
                                pfp: _pfp
                                sent: _sent
                                date: _date
                                sameAuthorAsBefore: index == msgModel.count-1 ? false : (msgModel.get(index+1)._author == _author)
                                masterWidth: sameAuthorAsBefore ? msgModel.get(index+1)._masterWidth : -1
                                masterDate: index == msgModel.count-1 ? new Date(1) : msgModel.get(index+1)._date
                                attachments: _attachments
                                reference: _ref
                                flags: _flags

                                function updateMasterWidth() {
                                    msgModel.setProperty(index, "_masterWidth", masterWidth == -1 ? innerWidth : masterWidth)
                                }

                                Component.onCompleted: {
                                    updateMasterWidth()
                                }
                                onMasterWidthChanged: updateMasterWidth()
                                onInnerWidthChanged: updateMasterWidth()
                            }
                        }

                        Component {
                            id: systemItem
                            SystemMessageItem { _model: model; label.horizontalAlignment: Text.AlignHCenter }
                        }
                    }

                }
            }

            Row {
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                visible: sendPermissions

                TextArea {
                    id: sendField
                    width: parent.width - sendButton.width

                    placeholderText: qsTr("Type something")
                    hideLabelOnEmptyField: false
                    labelVisible: false
                    anchors.verticalCenter: parent.verticalCenter
                    backgroundStyle: TextEditor.UnderlineBackground
                    horizontalAlignment: TextEdit.AlignLeft

                    EnterKey.iconSource: appSettings.sendByEnter ? "image://theme/icon-m-enter-accept" : ""
                    EnterKey.onClicked: if (appSettings.sendByEnter) sendMessage()
                }

                IconButton {
                    id: sendButton
                    width: Theme.iconSizeMedium + 2 * Theme.paddingSmall
                    height: width
                    enabled: sendField.text.length !== 0
                    anchors.bottom: parent.bottom
                    icon.source: "image://theme/icon-m-send"

                    onClicked: sendMessage()
                }
            }
        }

        PushUpMenu {
            visible: isDM
            MenuItem {
                text: qsTranslate("AboutUser", "About", "User")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutUserPage.qml"), { userid: userid, name: name, icon: usericon })
            }
        }
    }

    ListModel {
        id: msgModel

        property int updateCounter: 0

        function combineObjects(obj1, obj2) {
            var res = obj1
            for (var attrname in obj2) {
                if (res[attrname] !== undefined && (typeof obj2[attrname] === 'object') && (typeof res[attrname] === 'object'))
                    res[attrname] = combineObjects(res[attrname], obj2[attrname])
                else res[attrname] = obj2[attrname]
            }
            return res
        }

        function appendDemo2(toAppend) {
            insert(0, combineObjects({type: '', messageId: '-1', userid: '-1',
                                      _from_history: true, _wasUpdated: false,
                                      _masterWidth: -1, _date: new Date(),
                                      _flags: {edit: false, bot: false, nickAvailable: false,
                                          system: false, color: undefined},
                                      _sent: false, _contents: "", _author: "unknown", _pfp: '',
                                         _ref: {}, _attachments: [],
                                  }, toAppend))
        }

        function appendDemo(isyou, thecontents, additionalOptions) {
            additionalOptions = additionalOptions !== undefined ? additionalOptions : {}
            appendDemo2(combineObjects(
                            {_sent: isyou, _contents: thecontents, _author: isyou ? "you" : "notyou", _pfp: "https://cdn.discordapp.com/embed/avatars/"+(isyou ? "0" : "1")+".png"},
                            additionalOptions))
        }

        function generateDemo() {
            var repeatString = function(string, count) {
                var result = "";
                for (var i = 0; i < count; i++) result += string;
                return result;
            }

            // Append demo messages
            appendDemo(true, "First message!")
            appendDemo(true, "Second message")
            appendDemo(true, "A l "+repeatString("o ", 100)+"ng message.")

            appendDemo(false, "First message!")
            appendDemo(false, "Second message")
            appendDemo(false, "A l "+repeatString("o ", 100)+"ng message.")

            appendDemo(true, repeatString("Hello, world. ", 50))
            appendDemo(true, "Second message")
            appendDemo(true, "A l "+repeatString("o ", 100)+"ng message.")

            appendDemo(false, repeatString("Hello, world. ", 50))
            appendDemo(false, "Second message")
            appendDemo(false, "A l "+repeatString("o ", 100)+"ng message.")

            appendDemo(false, "Some long messages...")


            // TODO: attachments and replies
            //appendDemo(true, "Hey everyone, look at this pic!", {_attachments: [{}]})

            appendDemo2({_contents: "I am a normal guy, just have a colored nickname", _author: "normal_guy", _pfp: "https://cdn.discordapp.com/embed/avatars/4.png", _flags: {color:"green"}})
            appendDemo2({_contents: "I am a system guy", _pfp: "https://cdn.discordapp.com/embed/avatars/3.png", _flags: {system:true}})
            appendDemo2({_contents: "I am a bot!", _author: "a_bot", _pfp: "https://cdn.discordapp.com/embed/avatars/2.png", _flags: {bot:true}})
            appendDemo(true, "Edited message...", {_flags: {edit: true}})
            appendDemo(true, "First message!")
        }

        Component.onCompleted: {
            if (isDemo) generateDemo()
            else shared.registerMessageCallbacks(guildid, channelid, function(history, data) {
                if (history) msgModel.append(data); else msgModel.insert(0, data)
            })
        }

        onCountChanged: messagesList.forceLayout()
    }

    Component.onCompleted: {
        if (isDemo) {
            name = "demo-channel"
            guildid = -5
            channelid = -5
            return
        }

        python.setCurrentChannel(guildid, channelid)
        if (appSettings.focudOnChatOpen) activeFocusTimer.start()
    }

    Component.onDestruction: {
        if (isDemo) return
        shared.cleanupMessageCallbacks()
        python.resetCurrentChannel()
    }
}
