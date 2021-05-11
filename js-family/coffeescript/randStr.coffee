###*
	* Simple Random String Generator In Coffeescript
	* @author Jackson Roberts <jackson@holopanio.com>
###

randStr = (length) =>
	res = []
	chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	charsLength = chars.length

	res.push chars.charAt(Math.floor(Math.random() * charsLength)) for x in [1...length]

	return res.join ''

# Example
console.log randStr 7