import QtQuick 2.0
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.5
import "../components"


Page {
    id: page

    // The effective value will be restricted by ApplicationWindow.allowedOrientations
    allowedOrientations: Orientation.All

    property bool loading: true
    property bool loggingIn: false
    property string username: ""

    property alias serversModel: serversModel
    Timer {
        //credit: Fernschreiber
        id: openLoginDialogTimer
        interval: 0
        onTriggered: {
            pageStack.push(Qt.resolvedUrl("LoginDialog.qml"))
        }
    }

    function updatePage() {
        if (appConfiguration.token == "" && !loggingIn) {
            loggingIn = true
            loading = false
            openLoginDialogTimer.start()
        } else { // logged in, connect with python
            loggingIn = false
            python.login(appConfiguration.token)
        }

        if (!appConfiguration.usernameTutorialCompleted) completeTutorialTimer.start()
    }

    Connections {
        target: appConfiguration
        onTokenChanged: updatePage()
        onUsernameTutorialCompletedChanged: updatePage()
    }

    Component.onCompleted: updatePage()

    SilicaListView {
        id: firstPageContainer
        anchors.fill: parent

        VerticalScrollDecorator {}
        BusyLabel { running: loading }

        PullDownMenu {
            MenuItem {
                text: qsTranslate("AboutApp", "About", "App")
                onClicked: pageStack.push("AboutPage.qml")
            }
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push("SettingsPage.qml")
            }
        }

        header: PageHeader {
            title: username

            MouseArea {
                anchors.fill: parent
                onClicked: pageStack.push(Qt.resolvedUrl("AboutUserPage.qml"), { isClient: true, name: username, icon: "" })
            }
            TapInteractionHint {
                id: tapHint
                anchors.centerIn: parent
                taps: 1
                running: !appConfiguration.usernameTutorialCompleted
            }
        }

        InteractionHintLabel {
            id: hintText
            anchors.bottom: parent.bottom
            text: "Tap your username to access information"
            Behavior on opacity { FadeAnimation {} }
            visible: opacity > 0
            opacity: appConfiguration.usernameTutorialCompleted ? 0 : 1
        }

        Timer {
            id: completeTutorialTimer
            interval: 4000
            onTriggered: appConfiguration.usernameTutorialCompleted = true
        }

        model: serversModel

        delegate: Loader {
            sourceComponent: folder ? serverFolderComponent : serverItemComponent
            Component.onCompleted: if (folder) console.log(JSON.stringify(serversModel.get(index)))
            Component {
                id: serverItemComponent
                ServerListItem {
                    serverid: _id
                    title: name
                    icon: image
                    members: memberCount
                }
            }

            Component {
                id: serverFolderComponent
                // TODO: ColumnView
                Item {
                    Component.onCompleted: console.log("Hello, World from a folder!")
                }
            }
        }

        section {
            property: "_id"
            delegate: Loader {
                width: parent.width
                sourceComponent:section == serversModel.get(0)._id ? undefined : separatorComponent
                    /*serversModel.get(Number(section)).folderDisplayed ? folderComponent :
                        (section == 0 ? undefined : separatorComponent)
                Component.onCompleted: if (section == 0) console.log(serversModel.get(Number(section)).folderDisplayed)

                Component {
                    id: folderComponent
                    SectionHeader {
                        Rectangle {
                            anchors.fill: parent
                            color: serversModel.get(Number(section)).folder.color
                            z: -1
                        }
                        text: serversModel.get(Number(section)).folder.name
                    }
                }*/
                Component {
                    id: separatorComponent
                    Separator {
                        color: Theme.primaryColor
                        width: parent.width
                        horizontalAlignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }

    ListModel {
        id: serversModel

        function find(pattern) {
            for (var i = 0; i<count; i++) if (pattern(get(i))) return get(i)
            return null
        }

        function findById(_id) { return find(function (item) { return item.id === _id }) }
    }
}
