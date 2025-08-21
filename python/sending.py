from __future__ import annotations
import re
from typing import Any, List
from pyotherside import send as qsend
from threading import Thread
from enum import Enum

from caching import Cacher, ImageType
from utils import *

import discord


SUPPORTED_ANIMATED_STICKER_FORMATS = {discord.StickerFormatType.gif}#, discord.StickerFormatType.lottie}
SUPPORTED_STICKER_FORMATS = SUPPORTED_ANIMATED_STICKER_FORMATS | {discord.StickerFormatType.png}

# Servers

def gen_server(g: discord.Guild, cacher: Cacher):
    return (str(g.id), g.name, cacher.easy(g.icon, g.id, ImageType.SERVER))

def send_servers(guilds: List[discord.Guild | discord.GuildFolder | Any], cacher: Cacher):
    for g in guilds:
        if isinstance(g, discord.Guild):
            qsend('server', *gen_server(g, cacher))
        elif isinstance(g, discord.GuildFolder):
            qsend('serverfolder', str(g.id), g.name or '', hex_color(g.color), [gen_server(i, cacher) for i in g.guilds])

# Channels (shared)

async def send_channel_states(channels: List[discord.TextChannel | discord.DMChannel | Any], my_id = None, stop_checker = lambda: False):
    for c in channels:
        if stop_checker(): break
        if not isinstance(c, (discord.TextChannel, discord.DMChannel, discord.GroupChannel)) or c.mention_count or not (permissions_for(c, my_id).view_channel if my_id is not None else True):
            continue
        if await is_channel_unread(c):
            if isinstance(c, discord.TextChannel):
                qsend(f'channelUpdate{c.guild.id}', str(c.id), True, c.mention_count)
            else:
                qsend(f'dmUpdate', str(c.id), True, c.mention_count)

# Server Channels

async def send_channel(c: discord.abc.GuildChannel, myself_id):
    if c.type == discord.ChannelType.category:
        return
    #category_position = getattr(c.category, 'position', -1)+1 # Position is used instead of ID
    perms = permissions_for(c, myself_id)
    read_args = (bool(c.mention_count), #or await is_channel_unread(c, False)
    c.mention_count) if isinstance(c, discord.TextChannel) else (False, 0)
    qsend(f'channel{c.guild.id}', c.id, getattr(c.category, 'name', ''),
            str(c.id), c.name, perms.view_channel, str(c.type.name),
            isinstance(c, discord.TextChannel) and perms.send_messages, # If sending text is allowed
            perms.manage_messages, getattr(c, 'topic', '') or '',
            *read_args,
    )

def send_channels(guild: discord.Guild, user_id, async_runner, send_unread = False, current_server = None):
    for c in guild.channels:
        if c.category == None and not c.type == discord.ChannelType.category:
            async_runner(send_channel(c, user_id))
    for category in guild.categories:
        for c in category.channels:
            async_runner(send_channel(c, user_id))
    if send_unread:
        Thread(target=async_runner, args=(send_channel_states(guild.channels, user_id, lambda: (current_server() != guild) if callable(current_server) else False),)).start()

# DMs
# Keep in mind that DMs or groups don't have permissions and calling permissions_for returns dummy permissions

def send_dm_channel(channel: discord.DMChannel | discord.GroupChannel | Any, cacher: Cacher):
    base = (str(channel.id),
        *((bool(channel.mention_count), channel.mention_count) if isinstance(channel, (discord.DMChannel, discord.GroupChannel)) else (False, 0)),
    )

    if isinstance(channel, discord.DMChannel):
        user = channel.recipient
        icon = cacher.easy(user.display_avatar, user.id, ImageType.USER)
        qsend('dm', *base, user.display_name, icon, not user.system, str(user.id))
    elif isinstance(channel, discord.GroupChannel):
        icon = cacher.easy(channel.icon, channel.id, ImageType.GROUP)
        name, icon_base = group_name(channel)
        qsend('group', *base, name, icon, icon_base)
    else:
        show_error('unknownPrivateChannel', type(channel).__name__)

def send_dms(channel_list: List[discord.DMChannel | discord.GroupChannel | Any], cacher: Cacher, async_runner, send_unread = False):
    for channel in channel_list:#sorted(channel_list, key=lambda u: u.last_viewed_timestamp, reverse=True):
        send_dm_channel(channel, cacher)
    # This might not be needed (except for muted maybe)
    if send_unread:
        Thread(target=async_runner, args=(send_channel_states(channel_list),)).start()

# Messages

class AttachmentMapping(Enum):
    UNKNOWN = 0
    IMAGE = 1
    ANIMATED_IMAGE = 2

    @classmethod
    def from_attachment(cls, attachment: discord.Attachment):
        t, subtype, *_ = (attachment.content_type or '').split(';')[0].split('/') # e.g.: image/png for image
        if t == 'image':
            return cls.ANIMATED_IMAGE if attachment.flags.animated else cls.IMAGE
        else: return cls.UNKNOWN

def convert_attachments(attachments: list[discord.Attachment]):
    """Converts to QML-friendly attachment format, object (dict)"""
    # TODO: caching, more types
    res = [{
        "maxheight": -2,
        "maxwidth": -2,
        "filename": a.filename,
        "_height": a.height,
        "type": AttachmentMapping.from_attachment(a).value,
        "realtype": (a.content_type or '').split(';')[0],
        "url": a.proxy_url or a.url or '',
        "alt": a.description or '',
        "spoiler": a.is_spoiler(),
    } for a in attachments]
    if len(res) > 0:
        res[0]['maxheight'] = max((a.height or -1) if (a.content_type or '').startswith('image') else -1 for a in attachments)
        res[0]['maxwidth'] = max((a.width or -1) if (a.content_type or '').startswith('image') else -1 for a in attachments)
    return res

def generate_stickers(stickers: list[discord.StickerItem], cacher: Cacher):
    return [cacher.easy(s.url, s.id, ImageType.STICKER, animated = s.format in SUPPORTED_ANIMATED_STICKER_FORMATS)
        for s in stickers if s.format in SUPPORTED_STICKER_FORMATS]
    

def generate_extra_message(message: discord.Message | discord.MessageSnapshot, cacher: Cacher | None = None, emoji_size: Any | None = None, ref={}):
    t = message.type
    if t == discord.MessageType.new_member:
        return 'newmember', ()
    re.sub(r'<(?!)', r'\<', message.content)
    content = message.content.replace('<', '\\<')
    content = emojify(content, cacher, emoji_size, CUSTOM_EMOJI_RE_ESCAPED, 1) if isinstance(message, discord.Message) else content
    if t in (discord.MessageType.default, discord.MessageType.reply):
        return 'message', (message.content, content, ref or {})
    else: return 'unknownmessage', (message.content, content, ref or {}, message.type.name)

def generate_base_message(message: discord.Message | Any, cacher: Cacher, myself_id, is_history=False):
    """Returns a sequence of the base author-dependent message callback arguments to pass at the start"""

    return (str(message.guild.id) if message.guild else '-2', str(message.channel.id),
            str(message.id), qml_date(message.created_at),
            bool(message.edited_at), qml_date(message.edited_at) if message.edited_at else None,

            {
                'bot': message.author.bot, 'system': message.author.system,
                'sent': message.author.id == myself_id,

                'id': str(message.author.id),
                'name': message.author.display_name,
                'color': hex_color(message.author.color),

                'avatar': cacher.easy(message.author.display_avatar, message.author.id, ImageType.USER),
                'decoration': cacher.easy(message.author.avatar_decoration, message.author.avatar_decoration_sku_id, ImageType.DECORATION),
            },
            
            is_history, convert_attachments(message.attachments),
            message.jump_url,
            generate_stickers(message.stickers, cacher),
        )

# About

def send_user(user: discord.MemberProfile | discord.UserProfile):
    status, is_on_mobile = 0, False # default
    if isinstance(user, discord.MemberProfile):
        if StatusMapping.has_value(user.status):
            status = StatusMapping(user.status).index
        is_on_mobile = user.is_on_mobile()
    qsend(f'user{user.id}', user.bio or '', qml_date(user.created_at), status, is_on_mobile, #str(user.display_avatar), 
    usernames(user), user.bot, user.system, user.is_friend(), hex_color(user.color))

def send_myself(client: discord.Client):
    user = client.user
    status = 0 # default
    if StatusMapping.has_value(client.status):
        status = StatusMapping(client.status).index

    # We are not bots or system users. Or are we?
    qsend('user', user.bio or '', qml_date(user.created_at), status, client.is_on_mobile(), usernames(client.user))

def send_guild_info(g: discord.Guild):
    qsend(f'serverinfo{g.id}',
        #g.icon,
        str(-1 if g.member_count is None else g.member_count),
        str(-1 if g.online_count is None else g.online_count),
        {feature.lower(): feature in g.features for feature in
            ('VERIFIED','PARTNERED','COMMUNITY','DISCOVERABLE','FEATURABLE')
        },
        g.description or '',
    )