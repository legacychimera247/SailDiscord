import sys
import logging
from typing import Any, List
from pyotherside import send as qsend

from caching import Cacher, ImageType
from utils import *

script_path = Path(__file__).absolute().parent # /usr/share/harbour-saildiscord/python
sys.path.append(str(script_path.parent / 'lib/deps')) # /usr/share/harbour-saildiscord/lib/deps
import discord

# Servers

def gen_server(g: discord.Guild, cacher: Cacher):
    icon = '' if g.icon == None else \
            str(cacher.get_cached_path(g.id, ImageType.SERVER, default=g.icon))
    if icon != '':
        cacher.cache_image_bg(str(g.icon), g.id, ImageType.SERVER)
    return (str(g.id), g.name, icon)

def send_servers(guilds: List[Union[discord.Guild, discord.GuildFolder]], cacher: Cacher):
    for g in guilds:
        if isinstance(g, discord.Guild):
            qsend('server', *gen_server(g, cacher))
        elif isinstance(g, discord.GuildFolder):
            qsend('serverfolder', str(g.id), g.name or '', hex_color(g.color), [gen_server(i, cacher) for i in g.guilds])

# Server Channels

def send_channel(c, myself_id):
    if c.type == discord.ChannelType.category:
        return
    #category_position = getattr(c.category, 'position', -1)+1 # Position is used instead of ID
    qsend(f'channel{c.guild.id}', c.id, getattr(c.category, 'name', ''),
            str(c.id), str(c.name), permissions_for(c, myself_id).view_channel,
            str(getattr(getattr(c, 'type'), 'name')),
            c.type == discord.ChannelType.text and permissions_for(c, myself_id).send_messages, # If sending text is allowed
    )

def send_channels(guild: discord.Guild, user_id):
    for c in guild.channels:
        if c.category == None and not (getattr(c, 'type') == discord.ChannelType.category or isinstance(c, discord.CategoryChannel)):
            send_channel(c, user_id)
    for category in guild.categories:
        for c in category.channels:
            send_channel(c, user_id)

# DMs

def send_dm_channel(user: discord.User, cacher: Cacher):
    c = user.dm_channel
    icon = '' if user.display_avatar == None else \
            str(cacher.get_cached_path(user.id, ImageType.USER, default=user.display_avatar))
    if icon != '':
        cacher.cache_image_bg(str(user.display_avatar), user.id, ImageType.USER)
    qsend('dm', str(user.id), user.display_name, icon, str(user.dm_channel.id), user.dm_channel.permissions_for(user.dm_channel.me).view_channel)

def send_dms(users_list: List[discord.User], cacher: Cacher):
    for user in users_list:
        if isinstance(user, discord.ClientUser):
            continue
        if user.dm_channel:
            send_dm_channel(user, cacher)

# Messages

def generate_base_message(message: Union[discord.Message, Any], cacher: Cacher, myself_id, is_history=False):
    """Returns a sequence of the base author-dependent message callback arguments to pass at the start"""
    icon = '' if message.author.display_avatar == None else \
            str(cacher.get_cached_path(message.author.id, ImageType.USER, default=message.author.display_avatar))
    
    if icon != '':
        cacher.cache_image_bg(str(message.author.display_avatar), message.author.id, ImageType.USER)
    
    return (str(message.guild.id) if message.guild else '-2', str(message.channel.id),
            str(message.id), qml_date(message.created_at),
            bool(message.edited_at),

            {"id": str(message.author.id), "sent": message.author.id == myself_id,
            "name": str(getattr(message.author, 'nick', None) or message.author.name),
            "nick_avail": bool(getattr(message.author, 'nick', None)), # hasattr doesn't handle None values
            "pfp": icon, "bot": message.author.bot, "system": message.author.system,
            "color": hex_color(message.author.color)},
            
            is_history, convert_attachments(message.attachments, cacher)
        )

# About

def send_user(user: Union[discord.MemberProfile, discord.UserProfile]):
    status, is_on_mobile = 0, False # default
    if isinstance(user, discord.MemberProfile):
        if StatusMapping.has_value(user.status):
            status = StatusMapping(user.status).index
        is_on_mobile = user.is_on_mobile()
    qsend(f"user{user.id}", user.bio or '', qml_date(user.created_at), status, is_on_mobile, user.name, user.bot, user.system, hex_color(user.color))

def send_myself(client: discord.Client, cacher: Cacher):
    user = client.user
    status = 0 # default
    if StatusMapping.has_value(client.status):
        status = StatusMapping(client.status).index

    icon = '' if user.display_avatar == None else \
            str(cacher.get_cached_path(user.id, ImageType.MYSELF, default=user.display_avatar))

    # We are not bots or system users. Or are we?
    qsend("user", user.bio or '', qml_date(user.created_at), status, client.is_on_mobile(), icon)

    if icon != '':
        cacher.cache_image_bg(str(user.display_avatar), user.id, ImageType.MYSELF)

def send_guild_info(g: discord.Guild):
    qsend(f'serverinfo{g.id}',
        str(-1 if g.member_count is None else g.member_count),
        str(-1 if g.online_count is None else g.online_count),
        {feature.lower(): feature in g.features for feature in
            ('VERIFIED','PARTNERED','COMMUNITY','DISCOVERABLE','FEATURABLE')
        },
    )