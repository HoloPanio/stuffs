###*
	* Simple express webapp using coffeescript
	*
	* If you run this and goto your `http://localhost:42069/teapot`, you'll be told
	* that it isn't a teapot
	*
	* @author Jackson Roberts <jackson@holopanio.com>
###
express = require 'express'
app = express()

app.get '/teapot', (req, res) =>
	response = 
		status: 418
		message: "I'm a teapot"
	
	res.status(418).json response

app.listen 42069, () => console.log "now listening on port", 42069