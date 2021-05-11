###*
	* A simple fizz buzz script written in coffeescript
	* @author Jackson Roberts <jackson@holopanio.com>
###
fizzBuzz = (num) =>
	i = 0;
	while i < num
		i++

		fb = ''
		fb += 'Fizz' if i % 2 is 0
		fb += 'Buzz' if i % 5 is 0

		if fb is '' then console.log i
		else console.log fb

fizzBuzz 69