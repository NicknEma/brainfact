package brainfact;

import "core:io";
import "core:os";
import "core:fmt";
import "core:bufio";

import "core:strings";
import slices "core:slice";

import "core:runtime";
import "core:intrinsics";

_ :: io;
_ :: os;
_ :: fmt;
_ :: bufio;

_ :: slices;
_ :: strings;

_ :: runtime;
_ :: intrinsics;

run_program :: proc(program: []u8, memory: []u8) -> (success: bool) {
	ip: int;
	dp: int;
	
	Stack :: struct {
		data: [256]int,
		top:  int,
	}
	
	push :: proc(s: ^Stack, x: int) -> (res: bool) #no_bounds_check {
		if s.top < 0 do assert(false);
		
		if s.top < len(s.data) {
			s.data[s.top] = x;
			s.top += 1;
			
			res = true;
		} else {
			res = false;
		}
		
		return;
	}
	
	pop :: proc(s: ^Stack) -> (x: int, res: bool) #no_bounds_check {
		if s.top > len(s.data) - 1 do assert(false);
		
		if s.top > 0 {
			s.top -= 1;
			x = s.data[s.top];
			
			res = true;
		} else {
			res = false;
		}
		
		return;
	}
	
	top :: proc(s: ^Stack) -> (x: int, res: bool) #no_bounds_check {
		if s.top > len(s.data) - 1 do assert(false);
		
		if s.top > 0 {
			x = s.data[s.top - 1];
			
			res = true;
		} else {
			res = false;
		}
		
		return;
	}
	
	depth_stack: Stack;
	
	success = true;
	#no_bounds_check program_loop: for ip < len(program) {
		instr := program[ip];
		switch instr {
			case '>': {
				dp += 1;
				if intrinsics.expect(dp > len(memory) - 1, false) do dp = 0;
				
				ip += 1;
			}
			
			case '<': {
				dp -= 1;
				if intrinsics.expect(dp < 0, false) do dp = len(memory) - 1;
				
				ip += 1;
			}
			
			case '+': {
				memory[dp] += 1;
				ip += 1;
			}
			
			case '-': {
				memory[dp] -= 1;
				ip += 1;
			}
			
			case '[': {
				if memory[dp] == 0 {
					start_top := depth_stack.top;
					
					depth := 1;
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
					
					if new_ip == ip { // No matching ] was found.
						fmt.eprintf("[%i] Syntax error: '[' has no corresponding ']'\n", ip);
						success = false;
						break program_loop;
					}
					
					ip = new_ip;
				} else {
					push_success := push(&depth_stack, ip);
					if !push_success {
						fmt.eprintf("[%i] Stack overflow: The program is too complex and it overflew the interpreter's stack!", ip);
						success = false;
						break program_loop;
						
						// @Cleanup: Reallocate and try again instead of exiting?
					}
					ip += 1;
				}
			}
			
			case ']': {
				if memory[dp] != 0 {
					new_ip, is_balanced := top(&depth_stack);
					if is_balanced {
						ip = new_ip + 1;
					} else { // No matching [ was found.
						fmt.eprintf("[%i] Syntax error: ']' has no corresponding '['\n", ip);
						success = false;
						break program_loop;
					}
				} else {
					_, _ = pop(&depth_stack);
					ip += 1;
				}
			}
			
			// @Incomplete: Check for io errors? (What should it even do when they happen?)
			case '.': {
				err := bufio.writer_write_byte(&program_writer, memory[dp]);
				
				ip += 1;
			}
			
			case ',': {
				bufio.writer_flush(&program_writer);
				val, err := bufio.reader_read_byte(&program_reader);
				memory[dp] = val;
				
				ip += 1;
			}
			
			case: ip += 1;
		}
	}
	
	bufio.writer_flush(&program_writer);
	return;
}
