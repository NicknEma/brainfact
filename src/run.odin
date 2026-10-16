package brainfact

import "base:intrinsics"

import "core:fmt"
import "core:bufio"

run_program :: proc(program: []u8, memory: []u8, reader: bufio.Reader, writer: bufio.Writer) -> (success: bool) {
	// The depth stack, used for jumping between [ and ].
	Stack :: struct {
		data: [256]int,
		top:  int,
	}
	
	// If the stack is not full, writes the argument at the current stack pointer and
	// increments the stack pointer, then returns 'true'.
	// If the stack is full, returns 'false'.
	@require_results
	push :: proc(s: ^Stack, x: int) -> (ok: bool) #no_bounds_check {
		ensure(s.top >= 0);
		
		if s.top < len(s.data) {
			s.data[s.top], ok = x, true;
			s.top += 1;
		} else {
			ok = false;
		}
		
		return;
	}
	
	// If the stack is not empty, decrements the stack pointer and then returns
	// the element that was at the top and 'true'.
	// If the stack is empty, returns 0 and 'false'.
	@require_results
	pop :: proc(s: ^Stack) -> (x: int, ok: bool) #no_bounds_check {
		ensure(s.top < len(s.data));
		
		if s.top > 0 {
			x, ok = s.data[s.top - 1], true;
			s.top -= 1;
		} else {
			x, ok = 0, false;
		}
		
		return;
	}
	
	// If the stack is not empty, returns the element at the top and 'true'.
	// If the stack is empty, returns 0 and 'false'.
	@require_results
	top :: proc(s: ^Stack) -> (x: int, ok: bool) #no_bounds_check {
		ensure(s.top < len(s.data));
		
		if s.top > 0 {
			x, ok = s.data[s.top - 1], true;
		} else {
			x, ok = 0, false;
		}
		
		return;
	}
	
	depth_stack: Stack;
	ip, dp: int; // Instruction pointer and data pointer
	
	reader := reader;
	writer := writer;
	
	success = true;
	#no_bounds_check program_loop: for ip < len(program) {
		instr := program[ip];
		switch instr {
		case '>': {
			dp += 1; // Increment the data pointer.
			if intrinsics.expect(dp > len(memory) - 1, false) {
				dp = 0;
			}
			
			ip += 1;
		}
		
		case '<': {
			dp -= 1; // Decrement the data pointer.
			if intrinsics.expect(dp < 0, false) {
				dp = len(memory) - 1;
			}
			
			ip += 1;
		}
		
		case '+': {
			memory[dp] += 1; // Increment the byte at the data pointer by one.
			ip += 1;
		}
		
		case '-': {
			memory[dp] -= 1; // Decrement the byte at the data pointer by one.
			ip += 1;
		}
		
		case '[': {
			// Instruction description: If the byte at the data pointer is zero, then
			// instead of moving the instruction pointer forward to the next command,
			// jump it forward to the command after the matching ] command.
			if memory[dp] == 0 {
				// Zero byte, jump to matching ].
				depth  := 1;
				new_ip := ip;
				for at := ip + 1; at < len(program) && new_ip == ip; at += 1 {
					if program[at] == '[' {
						depth += 1;
					} else if program[at] == ']' {
						depth -= 1;
						
						if depth == 0 {
							new_ip = at + 1;
						}
					}
				}
				
				if new_ip == ip {
					fmt.eprintfln("[%i] Syntax error: '[' has no corresponding ']'.", ip);
					success = false;
					break program_loop;
				}
				
				ip = new_ip;
			} else {
				// Nonzero byte, prepare to jump back to this [.
				if push_success := push(&depth_stack, ip); !push_success {
					fmt.eprintfln("[%i] Runtime panic: The program has too many nested loops (max depth is %v) and caused an overflow on the interpreter's stack.", len(depth_stack.data), ip);
					success = false;
					break program_loop;
				}
				
				ip += 1;
			}
		}
		
		case ']': {
			// Instruction description: If the byte at the data pointer is nonzero, then
			// instead of moving the instruction pointer forward to the next command,
			// jump it back to the command after the matching [ command.
			is_balanced: bool;
			if memory[dp] != 0 {
				// Nonzero byte, jump back to matching [.
				new_ip: int;
				if new_ip, is_balanced = top(&depth_stack); is_balanced {
					ip = new_ip + 1;
				}
			} else {
				// Zero byte, discard matching [ and continue.
				if _, is_balanced = pop(&depth_stack); is_balanced {
					ip += 1;
				}
			}
			
			if !is_balanced {
				fmt.eprintfln("[%i] Syntax error: ']' has no corresponding '['.", ip);
				success = false;
				break program_loop;
			}
		}
		
		case '.': {
			// Output the byte at the data pointer.
			err := bufio.writer_write_byte(&writer, memory[dp]);
			if err != nil {
				fmt.eprintfln("Could not write byte: %v.", err);
			}
			
			ip += 1;
		}
		
		case ',': {
			// Accept one byte of input, storing its value in the byte at the data pointer.
			bufio.writer_flush(&writer);
			val, err := bufio.reader_read_byte(&reader);
			if err != nil {
				fmt.eprintfln("Could not read byte: %v.", err);
			} else {
				memory[dp] = val;
			}
			
			ip += 1;
		}
		
		case: ip += 1; // Ignore anything else.
	}
	}
	
	bufio.writer_flush(&writer);
	return;
}
