import QtQuick 2.0
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.5
import "../components"
import "../modules/Opal/Tabs"

Page {
    allowedOrientations: Orientation.All

    property bool loading: true
    property string username: ""

    Timer {
        //credit: Fernschreiber
        id: openLoginDialogTimer
        interval: 0
        onTriggered: pageStack.push(Qt.resolvedUrl("LoginDialog.qml"))
    }

    function updatePage() {
        if (appConfiguration.token == "") {
            // For log out
            serversModel.clear()
            dmModel.clear()
            username = ""

            loading = false
            openLoginDialogTimer.start()
        } else { // logged in, connect with python
            loading = true
            python.login(appConfiguration.token)
        }
    }

    Connections {
        target: appConfiguration
        onTokenChanged: updatePage()
    }

    Component.onCompleted: {
        python.init(function(u) {
            loading = false
            username = u
        }, serversModel.append, dmModel.append, function() {
            serversModel.clear()
            dmModel.clear()
            username = ""
            updatePage()
        })
        updatePage()
    }

    BusyLabel { running: loading }

    SilicaFlickable {
        anchors.fill: parent

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: python.refresh()
            }
        }

        Column {
            anchors.fill: parent
            PageHeader { id: header; title: username }

            Row {
                width: parent.width
                height: parent.height - header.height
                SilicaListView {
                    width: Theme.itemSizeExtraLarge
                    height: parent.height
                    model: serversModel
                    VerticalScrollDecorator {}

                    delegate: Loader {
                        sourceComponent: folder ? null : serverItemComponent
                        width: parent.width
                        height: width
                        property var _color: folder ? color : undefined
                        property var _servers: folder ? servers : undefined
                        onStatusChanged: if (status == Loader.Ready) item.anchors.fill = item.parent

                        Component {
                            id: serverItemComponent
                            ListItem {
                                anchors.fill: parent
                                contentHeight: height

                                ListImage {
                                    icon: image
                                    anchors {
                                        fill: parent
                                        margins: Theme.paddingLarge
                                    }
                                    errorString: name
                                    anchors.centerIn: parent
                                    enabled: false
                                }

                                onClicked: pageStack.push(Qt.resolvedUrl("../pages/ChannelsPage.qml"), { serverid: _id, name: name, icon: image })
                                menu: Component { ContextMenu {
                                    visible: defaultActions
                                    MenuItem {
                                        text: qsTranslate("AboutServer", "About", "Server")
                                        onClicked: pageStack.push(Qt.resolvedUrl("../pages/AboutServerPage.qml"),
                                                                  { serverid: _id, name: name, icon: image }
                                                                  )
                                    }
                                } }
                            }
                        }

                        Component {
                            id: serverFolderComponent
                            Column {
                                width: parent.width
                                SectionHeader {
                                    id: folderHeader
                                    visible: name
                                    color: _color == "" ? palette.highlightColor : _color
                                    text: name
                                }
                                Row {
                                    width: parent.width
                                    Item {
                                        width: Theme.paddingLarge
                                        height: parent.height
                                        Rectangle {
                                            width: Theme.paddingSmall
                                            color: folderHeader.color
                                            height: parent.height
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }

                                    ColumnView {
                                        model: _servers
                                        delegate: serverItemComponent
                                        itemHeight: Theme.itemSizeLarge
                                    }
                                }
                            }
                        }
                    }

                    /*section {
                        property: "_id"
                        delegate: Loader {
                            width: parent.width
                            sourceComponent: section == serversModel.get(0)._id ? undefined : separatorComponent
                            Component {
                                id: separatorComponent
                                Separator {
                                    color: Theme.primaryColor
                                    width: parent.width
                                    horizontalAlignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }*/
                }
            }
        }
    }

    /*TabView {
        anchors.fill: parent
        tabBarPosition: Qt.AlignBottom
        currentIndex: 1
        interactive: !loading

        Tab {
            title: qsTr("DMs")
            Component {
                TabItem {
                    flickable: dmsContainer
                    SilicaFlickable {
                        id: dmsContainer
                        anchors.fill: parent

                        PullDownMenu {
                            MenuItem {
                                text: qsTr("Refresh")
                                onClicked: python.refresh()
                            }
                        }
                        PageHeader { id: header; title: username }

                        SilicaListView {
                            width: parent.width
                            anchors {
                                top: header.bottom
                                bottom: parent.bottom
                            }
                            clip: true
                            model: dmModel
                            VerticalScrollDecorator {}

                            delegate: ServerListItem {
                                serverid: '-1'
                                title: name
                                icon: image
                                defaultActions: false

                                onClicked: pageStack.push(Qt.resolvedUrl("MessagesPage.qml"), { guildid: '-2', channelid: dmChannel, name: name, sendPermissions: textSendPermissions, isDM: true, userid: _id, usericon: image })
                                menu: Component { ContextMenu {
                                    MenuItem {text: qsTranslate("AboutUser", "About", "User")
                                        visible: _id != '-1'
                                        onClicked: pageStack.push(Qt.resolvedUrl("AboutUserPage.qml"), { userid: _id, name: name, icon: image })
                                    }
                                } }
                            }

                            section {
                                property: "_id"
                                delegate: Loader {
                                    width: parent.width
                                    sourceComponent: section == dmModel.get(0)._id ? undefined : separatorComponent
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
                    }
                }
            }
        }

        Tab {
            title: qsTr("Servers")
            Component {
                TabItem {
                    flickable: serversContainer

                }
            }
        }

        Tab {
            title: qsTr("Me")

            Component {
                TabItem {
                    id: tabItem
                    flickable: morePage.flickable
                    //topMargin: -(parent._ctxTopMargin || _ctxTopMargin || 0) // a bug occuring when using with Opal.About: top margin goes away for some reason, and gets the header...
                    property string _username: username

                    AboutUserPage {
                        parent: null
                        anchors.fill: parent
                        flickable.parent: tabItem
                        id: morePage
                        isClient: true
                        name: _username
                        icon: ""

                        PullDownMenu {
                            parent: morePage.flickable
                            MenuItem {
                                text: qsTranslate("AboutApp", "About", "App")
                                onClicked: pageStack.push("AboutPage.qml")
                            }
                            MenuItem {
                                text: qsTr("Settings")
                                onClicked: pageStack.push("SettingsPage.qml")
                            }
                        }
                    }
                }
            }
        }
    }
*/
    /*TouchBlocker {
        anchors.fill: parent
        visible: false//loading
    }*/

    ListModel { id: serversModel }
    ListModel { id: dmModel }
}
