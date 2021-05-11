/**
 * A simple fizz buzz script written in JavaScript
 * @author Jackson Roberts <jackson@holopanio.com>
 */
function fizzBuzz(num){
	for(var i = 1; i <= num; i++) { 
		var ret = '';  
		if ((i % 2) == 0) ret += 'Fizz'; 
		if ((i % 5) == 0) ret += 'Buzz'; 
		
		console.log(((ret == '') ? i : ret)); 
	} 
} 

fizzBuzz(69);