import QtQuick 2.0
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.5
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.All

    property string serverid
    property string name
    property string icon
    property string memberCount

    SilicaFlickable {
        PageHeader {
            title: name
        }
    }
}
