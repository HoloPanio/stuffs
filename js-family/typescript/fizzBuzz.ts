function fizzBuzzTS(num: number): void{
	for(var i = 1; i <= num; i++) { 
		var ret = '';  
		if ((i % 2) == 0) ret += 'Fizz'; 
		if ((i % 5) == 0) ret += 'Buzz'; 
		
		console.log(((ret == '') ? i : ret)); 
	} 
} 

fizzBuzzTS(69);