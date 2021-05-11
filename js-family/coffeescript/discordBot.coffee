###*
	* A simple discord bot written in coffeescript
	* @author Jackson Roberts <jackson@holopanio.com>
###

Discord = require 'discord.js'
config = require './config'
app = new Discord.Client()

app.on 'ready', () =>
	console.log 'Logged into discord as', app.user.tag

app.on 'message', (msg) =>
	console.log "#{msg.author.tag}:", msg.content

app.login config.token