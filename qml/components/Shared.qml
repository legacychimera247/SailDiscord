import QtQuick 2.0
import Sailfish.Silica 1.0
import "../modules/js/showdown.min.js" as ShowDown
import "../modules/js/twemoji.min.js" as Twemoji
import '../modules/Opal/LinkHandler'

QtObject {
    property bool active: Qt.application.state === Qt.ApplicationActive
    property var showdown: new ShowDown.showdown.Converter({
            simplifiedAutoLink: true,
            underline: true,
            backslashEscapesHTMLTags: true,
        })

    // Signals
    signal serverAdded(string serverId, int mainIndex, int subIndex)

    // Shared
    function log() {
      var f = ""
      for (var i = 0; i < arguments.length; i++) {
        f += arguments[i]
        if (i != arguments.length-1) f += "|||"
      }
      console.log(f)
    }

    function arrayToListModel(_parent, arr) {
        // Make attachments a ListModel: a (bug?) which exists in QML and I have to enable it manually where it is fixed
        // Also see https://stackoverflow.com/questions/37069565/qml-listmodel-append-broken-for-object-containing-an-array
        var listModel = Qt.createQmlObject('import QtQuick 2.0;ListModel{}', _parent)
        arr.forEach(function(el, i) { listModel.append(el) })
        return listModel
    }

    function listModelToArray(model) {
        // see Shared.arrayToListModel
        // unused for now (didn't work as expected; strings got converted into QObjects, but normal JS objects were converted fine)
        if (Array.isArray(model) || !model) return model
        var arr = []
        for (var i=0; i<model.count; i++)
            arr.push(model.get(i))
        return arr
    }

    function combineObjects(obj1, obj2) {
        var res = obj1
        for (var attrname in obj2) {
            if (res[attrname] !== undefined && (typeof obj2[attrname] === 'object') && (typeof res[attrname] === 'object'))
                res[attrname] = combineObjects(res[attrname], obj2[attrname])
            else res[attrname] = obj2[attrname]
        }
        return res
    }

    function removeConfigurationValue(conf, value) {
        if (conf.value(value, null) !== null)
            conf.setValue(value, undefined)
    }

    // Text formatting
    function markdown(text, edited, secondaryLinkColor) {
        var e = emojify(text)
        return '<style>'
                    + 'a{color:' + (secondaryLinkColor ? Theme.secondaryColor : Theme.highlightColor) + ';}\n'
                    // this is from python:
                    + '.mention{background-color:' + Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity) + ';color:' + Theme.highlightColor + ';font-weight:bold;}'
                + '</style>'
                + showdown.makeHtml(((appSettings.twemoji && /^<img/.test(e)) ? '<span style="color:transparent">.</span>': '')
                                       +e
                                       +(edited ? ("<a href='sailcord://showEditDate' style='text-decoration:none;font-size:" + Theme.fontSizeExtraSmall + "px;color:"+ Theme.secondaryColor +";'>" + qsTr("(edited)") + "</a>") : "")
                                       )
    }

    function emojify(text) {
        if (!appSettings.twemoji) return text
        return Twemoji.twemoji.parse(text, { base: Qt.resolvedUrl('../../images/twemoji/'), attributes: function () { return { width: '%1'.arg(Theme.fontSizeMedium), height: '%1'.arg(Theme.fontSizeMedium) } } })
    }

    function handleLink(link, sailcordHandler) {
        if (link.indexOf('sailcord://') == 0) {
            var part = link.slice(11)
            var slashIndex = part.indexOf('/')
            var before = part.slice(0, slashIndex), after = part.slice(slashIndex + 1)
            // e.g. "sailcord://test/123" -> before="test", after="123"

            switch (before) {
            case 'user':
                pageStack.push("../pages/AboutUserPage.qml", {userid: after})
                return
            }

            if (sailcordHandler && sailcordHandler(before, after))
                return
        }
        LinkHandler.openOrCopyUrl(link)
    }

    // Notifications/errors
    function showInfo(summary, text) {
        notifier.appIcon = "image://theme/icon-lock-information"
        notifier.summary = summary || ''
        notifier.body = text || ''
        notifier.publish()
    }

    function showError(summary, text) {
        notifier.appIcon = "image://theme/icon-lock-warning"
        notifier.summary = summary || ''
        notifier.body = text || ''
        notifier.publish()
        console.log(summary, text)
    }

    // Files
    function download(url, name) {
        py.call('main.comm.download_file', [url, name], function(newName) {
            if (newName) showInfo(qsTr("Downloaded file %1").arg(newName))
            else showError(qsTranslate("Errors", "Unable to download file %1. Check recent errors").arg(name))
        })
    }

    function shareFile(url, name, mime) {
        py.call('main.comm.save_temp', [url, name], function(path) {
            if (!path) {
                showError(qsTranslate("Errors", "Unable to share file %1. Check recent errors").arg(name))
                return
            }

            shareApi.mimeType = mime
            shareApi.resources = [path]
            shareApi.trigger()
        })
    }

    // Messages
    property var stubMessage: ({
        type: '', messageId: '-1', userid: '-1',
        _from_history: true, _wasUpdated: false,
        _masterWidth: -1, date: new Date(),
        flags: {edit: false, bot: false, editedAt: undefined,
            system: false, color: undefined},
        sent: false, contents: "", formattedContents: "",
        author: "unknown", avatar: '',
        reference: {}, attachments: [],
        jumpUrl: '', highlightStarted: false,
        APIType: '', decoration: '',
        stickers: [],
    })
    function constructMessageCallback(type, guildid, channelid, finalCallback) {
        return function(_serverid, _channelid, _id, date, edited, editedAt, userinfo, history, attachments, jumpUrl, stickers) {
            if (guildid != undefined && channelid != undefined)
                if ((_serverid != guildid) || (_channelid != channelid)) return
            var data = {
                type: type, messageId: _id, author: emojify(userinfo.name), avatar: userinfo.avatar,
                sent: userinfo.sent, _masterWidth: -1, date: new Date(date), _from_history: history,
                _wasUpdated: false, userid: userinfo.id, attachments: attachments,
                flags: {
                    edit: edited, bot: userinfo.bot, editedAt: editedAt,
                    system: userinfo.system, color: userinfo.color
                },
                APIType: '', contents: '', formattedContents: '', reference: {}, highlightStarted: false,
                jumpUrl: jumpUrl, decoration: userinfo.decoration,
                stickers: stickers,
            }

            var extraStart = 11
            if (type === "" || type === "unknown") {
                data.contents = arguments[extraStart]
                data.formattedContents = markdown(arguments[extraStart+1], data.flags.edit)
                data.reference = arguments[extraStart+2]
            }
            if (type === "unknown") data.APIType = arguments[extraStart+3]
            finalCallback(history, data)
        }
    }

    function convertCallbackType(pyType) {
        switch(pyType) {
        case "message": return ''
        case "newmember": return 'join'
        case "unknownmessage": return 'unknown'
        }
    }

    function registerMessageCallbacks(guildid, channelid, finalCallback, editCallback) {
        // see convertCallbackType()
        py.setHandler("message", constructMessageCallback('', guildid, channelid, finalCallback))
        py.setHandler("newmember", constructMessageCallback('join', guildid, channelid, finalCallback))
        py.setHandler("unknownmessage", constructMessageCallback('unknown', guildid, channelid, finalCallback))
        py.setHandler("messageedit", function(before, event, args) {
            constructMessageCallback(convertCallbackType(event), guildid, channelid, function(history, data) {
                editCallback(before, data)
            }).apply(null, args)
        })
        py.setHandler("messagedelete", function(id) { editCallback(id) })
    }

    function cleanupMessageCallbacks() {
        // we unset handler so app won't crash on appending items to destroyed list because resetCurrentChannel is not instant
        py.reset("message")
        py.reset("newmember")
        py.reset("uknownmessage")
        py.reset("messageedit")
        py.reset("messagedelete")
    }

    // Servers, channels
    function processServer(_id, name, icon) {
        if (appConfiguration.legacyMode && _id == "1261605062162251848") {
            name = "RoundedRectangle's server"
            icon = {source: Qt.resolvedUrl("../images/%1.png".arg(Qt.application.name))} // todo
        }
        // heads up: QQMLListModel can convert:
        // arrays to QQMLListModel instances
        // undefined to empty objects aka {} when other elements are objects
        return {_id: _id, name: shared.emojify(name), image: icon,
            folder: false, color: '', servers: [], // QML needs same element keys in all model entries (if dynamicRoles is false; setting it to true impacts performance)
        }
    }

    function loadLastChannels() {
        try { return JSON.parse(appConfiguration.serverLastChannels) }
        catch(e) { appConfiguration.serverLastChannels = "{}"; return {} }
    }

    function getLastChannel(serverid) {
        var loaded = loadLastChannels()
        return serverid in loaded ? loaded[serverid] : '-1'
    }

    function setLastChannel(serverid, channelid) {
        var loaded = loadLastChannels()
        loaded[serverid] = channelid
        appConfiguration.serverLastChannels = JSON.stringify(loaded)
    }

    // User info
    function constructStatus(statusIndex, onMobile) {
        var result = ["",
                      qsTranslate("status", "Online"),
                      qsTranslate("status", "Offline"),
                      qsTranslate("status", "Do Not Disturb"),
                      qsTranslate("status", "Invisible"),
                      qsTranslate("status", "Idle")
                ][statusIndex]
        if (onMobile && result !== "")
            result += " "+qsTranslate("status", "(Phone)", "Used with e.g. Online (Phone)")
        return result
    }
}
