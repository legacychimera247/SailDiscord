import QtQuick 2.0
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0

ListItem {
    property string contents
    property string author
    property string pfp
    property bool sent // If the message is sent by the user connected to the client
    property bool sameAuthorAsBefore
    property date date

    property real masterWidth // Width of the previous element with pfp. Used with sameAuthorAsBefore
    property date masterDate // Date of previous element

    property bool _firstSameAuthor: switch(appSettings.messageGrouping) {
        case "n": return true
        case "a": return !sameAuthorAsBefore
        case "d": return !(sameAuthorAsBefore && (date - msgModel.get(index+1)._date) < 300000) // 5 minutes
    }
    property bool _sentLessWidth: (appSettings.messagesLessWidth && sent) ? Theme.paddingLarge : 0 // Width required to substract
    property real _infoWidth: profileIcon.width + iconPadding.width + leftPadding.width

    property alias innerWidth: row.width

    width: parent.width
    contentHeight: row.height

    Row {
        id: row
        //width: parent.width
        width: {
            if(_firstSameAuthor) {
                if (appSettings.sentBehaviour !== "n")
                    return Math.min(parent.width - _sentLessWidth,
                                    _infoWidth + Math.max(contentsLbl.implicitWidth, infoRow.width));
                else return parent.width-_sentLessWidth
            } else return Math.max(masterWidth,
                                   Math.min(parent.width-_sentLessWidth,
                                            _infoWidth + contentsLbl.implicitWidth));
        }
        height: !_firstSameAuthor ? textContainer.height : childrenRect.height
        // align right if sent and set to reversed/right aligned
        anchors.right: (sent && appSettings.sentBehaviour !== "n") ? parent.right : undefined
        // reverse if sent and set to reversed
        layoutDirection: (sent && appSettings.sentBehaviour === "r") ? Qt.RightToLeft : Qt.LeftToRight

        Item { id: leftPadding; height: 1; width: switch (appSettings.messagesPadding) {
           default: case "n": return 0
           case "s": return (visible && sent) ? Theme.horizontalPageMargin : 0
           case "r": return (visible && sent) ? 0 : Theme.horizontalPageMargin
           case "a": return visible ? Theme.horizontalPageMargin : 0
        }
            visible: _firstSameAuthor || appSettings.oneAuthorPadding !== "n"
        }

        Image {
            id: profileIcon
            source: _firstSameAuthor ? pfp : ""
            height: Theme.iconSizeLarge
            width: visible ? height : 0
            visible: _firstSameAuthor || (appSettings.oneAuthorPadding === "p")
            opacity: _firstSameAuthor ? 1 : 0

            property bool rounded: true
            property bool adapt: true

            layer.enabled: rounded
            layer.effect: OpacityMask {
                maskSource: Item {
                    width: profileIcon.width
                    height: profileIcon.height
                    Rectangle {
                        anchors.centerIn: parent
                        width: profileIcon.adapt ? profileIcon.width : Math.min(profileIcon.width, profileIcon.height)
                        height: profileIcon.adapt ? profileIcon.height : width
                        radius: Math.min(width, height)
                    }
                }
            }

            onStatusChanged: if (status == Image.Error)
                Notices.show(qsTranslate("Errors", "Error loading image %1. Please report this to developers").arg(author), Notice.Long, Notice.Top)

            ProgressCircle {
                id: progressCircle
                anchors.fill: parent
                visible: parent.status == Image.Loading

                Timer {
                    interval: 32
                    repeat: true
                    onTriggered: progressCircle.value = (progressCircle.value + 0.01) % 1.0
                    running: parent.parent.status == Image.Loading
                }
            }
        }

        Item { id: iconPadding; height: 1; width: visible ? Theme.paddingLarge : 0;
            // visible the same as for authorLbl or profileIcon; but if oneAuthorPadding is enabled then ignore everything and set to true
            visible: _firstSameAuthor || appSettings.oneAuthorPadding !== "n";
        }

        Column {
            id: textContainer
            width: {
                if(_firstSameAuthor) {
                    if (appSettings.sentBehaviour === "a") // If sentBehaviour is right-aligned,
                    return Math.min(parent.width - _infoWidth, Math.max(contentsLbl.paintedWidth, infoRow.width))
                    else return (parent.width - _infoWidth)
                } else return parent.width - _infoWidth;
            }
            Row {
                id: infoRow
                visible: _firstSameAuthor
                spacing: Theme.paddingSmall
                Label {
                    id: authorLbl
                    text: author
                    color: Theme.secondaryColor
                }

                Label {
                    id: timeLbl
                    text: Format.formatDate(date, Formatter.TimepointRelative)
                    color: Theme.secondaryHighlightColor
                }
            }

            Label {
                id: contentsLbl
                text: contents
                wrapMode: Text.Wrap
                width: Math.min(parent.width, implicitWidth)
                               // if sent, sentBehaviour is set to reversed or right-aligned, and aligning text is enabled
                anchors.right: (sent && appSettings.sentBehaviour !== "n" && appSettings.alignMessagesText) ? parent.right : undefined
            }

            Item { height: _firstSameAuthor ? Theme.paddingLarge : Theme.paddingSmall; width: 1; }
        }
    }
}
