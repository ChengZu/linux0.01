/*
 * to protected mode, and calls the start of system. System then must
 * RE-initialize the protected mode in it's own tables, and enable
 * interrupts as needed.
 *
 * NOTE! currently system is at most 8 *65536 bytes long. This should be no
 * problem, even in the future. I want to keep it simple. This 512 kB
 * kernel size should be enough - in fact more would mean we'd have to move
 * not just these start-up routines, but also do something about the cache-
 * memory (block IO devices). The area left over in the lower 640 kB is meant
 * for these. No other memory is assumed to be "physical", ie all memory
 * over 1Mb is demand-paging. All addresses under 1Mb are guaranteed to match
 * their physical addresses.
 *
 * NOTE1 abouve is no longer valid in it's entirety. cache-memory is allocated
 * above the 1Mb mark as well as below. Otherwise it is mainly correct.
 *
 * NOTE 2! The boot disk type must be set at compile-time, by setting
 * the following equ. Having the boot-up procedure hunt for the right
 * disk type is severe brain-damage.
 * The loader has been made as simple as possible (had to, to get it
 * in 512 bytes with the code to move to protected mode), and continuos
 * read errors will result in a unbreakable loop. Reboot by hand. It
 * loads pretty fast by getting whole sectors at a time whenever possible.
 */
.code16
# 1.44Mb disks:
sectors = 18
# 1.2Mb disks:
# sectors = 15
# 720kB disks:
# sectors = 9

.globl  _start, begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

BOOTSEG = 0x07c0
INITSEG = 0x9000
SYSSEG  = 0x1000			# system loaded at 0x10000 (65536).
ENDSEG	= SYSSEG + SYSSIZE

_start:
	movw	$BOOTSEG,%ax
	movw	%ax,%ds
	movw	$INITSEG,%ax
	movw	%ax,%es
	movw	$256,%cx
	sub	%si,%si
	sub	%di,%di
	rep
	movsw
	ljmp	$INITSEG,$go

go:	movw	%cs,%ax
	movw	%ax,%ds
	movw	%ax,%es
	movw	%ax,%ss
	movw	$0x400,%sp	# arbitrary value >>512

	movb	$0x03,%ah	# read cursor pos
	xorb	%bh,%bh
	int	$0x10
	
	movw	$24,%cx
	movw	$0x0007,%bx	# page 0, attribute 7 (normal)
	movw	$msg1,%bp
	movw	$0x1301,%ax	# write string, move cursor
	int	$0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

	movw	$SYSSEG,%ax
	movw	%ax,%es		# segment of 0x010000

	call	read_it
	call	kill_motor

# if the read went well we get current cursor position ans save it for
# posterity.

	mov	$0x03,%ah	# read cursor pos
	xor	%bh,%bh
	int	$0x10		# save it in known place, con_init fetches
	mov	%dx,(510)	# it from 0x90510.
		
# now we want to move to protected mode ...

	cli			# no interrupts allowed !

# first we move the system to it's rightful place

	mov	$0x0000,%ax
	cld			# 'direction'=0, movs moves forward
do_move:
	mov	%ax,%es		# destination segment
	add	$0x1000,%ax
	cmp	$0x9000,%ax
	jz	end_move
	mov	%ax,%ds		# source segment
	sub	%di,%di
	sub	%si,%si
	mov 	$0x8000,%cx
	rep
	movsw
	jmp	do_move

# then we load the segment descriptors

end_move:

	mov	%cs,%ax		# right, forgot this at first. didn't work :-)
	mov	%ax,%ds
	lidt	idt_48		# load idt with 0,0
	lgdt	gdt_48		# load gdt with whatever appropriate

# that was painless, now we enable A20

	call	empty_8042
	mov	$0xD1,%al		# command write
	out	%al,$0x64
	call	empty_8042
	mov	$0xDF,%al		# A20 on
	out	%al,$0x60
	call	empty_8042

# well, that went ok, I hope. Now we have to reprogram the interrupts :-(
# we put them right after the intel-reserved hardware interrupts, at
# int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
# messed this up with the original PC, and they haven't been able to
# rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
# which is used for the internal hardware interrupts as well. We just
# have to reprogram the 8259's, and it isn't fun.

	mov	$0x11,%al		# initialization sequence
	out	%al,$0x20		# send it to 8259A-1
	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2
	out	%al,$0xA0		# and to 8259A-2
	.word	0x00eb,0x00eb
	mov	$0x20,%al		# start of hardware int's (0x20)
	out	%al,$0x21
	.word	0x00eb,0x00eb
	mov	$0x28,%al		# start of hardware int's 2 (0x28)
	out	%al,$0xA1
	.word	0x00eb,0x00eb
	mov	$0x04,%al		# 8259-1 is master
	out	%al,$0x21
	.word	0x00eb,0x00eb
	mov	$0x02,%al		# 8259-2 is slave
	out	%al,$0xA1
	.word	0x00eb,0x00eb
	mov	$0x01,%al		# 8086 mode for both
	out	%al,$0x21
	.word	0x00eb,0x00eb
	out	%al,$0xA1
	.word	0x00eb,0x00eb
	mov	$0xFF,%al		# mask off all interrupts for now
	out	%al,$0x21
	.word	0x00eb,0x00eb
	out	%al,$0xA1

# well, that certainly wasn't fun :-(. Hopefully it works, and we don't
# need no steenking BIOS anyway (except for the initial loading :-).
# The BIOS-routine wants lots of unnecessary data, and it's less
# "interesting" anyway. This is how REAL programmers do it.
#
# Well, now's the time to actually move into protected mode. To make
# things as simple as possible, we do no register set-up or anything,
# we let the gnu-compiled 32-bit programs do that. We just jump to
# absolute address 0x00000, in 32-bit protected mode.

	mov	$0x0001,%ax	# protected mode (PE) bit
	lmsw	%ax		# This is it!
	###jmpi	0,8		# jmp offset 0 of segment 8 (cs)
	ljmp	$8,$0



# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	$0x64,%al	# 8042 status port
	test	$2,%al		# is input buffer full?
	jnz	empty_8042	# yes - loop
	ret

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
# This routine has to be recompiled to fit another drive type,
# just change the "sectors" variable at the start of the file
# (originally 18, for a 1.44Mb drive)
#
sread:	.word 1			# sectors read of current track
head:	.word 0			# current head
track:	.word 0			# current track
read_it:
	mov %es,%ax
	test $0x0fff,%ax
die:	jne die			# es must be at 64kB boundary
	xor %bx,%bx		# bx is starting address within segment
rp_read:
	mov %es,%ax
	cmp $ENDSEG,%ax		# have we loaded all yet?
	jb ok1_read
	ret
ok1_read:
	mov $sectors,%ax
	sub sread,%ax
	mov %ax,%cx
	shl $9,%cx
	add %bx,%cx
	jnc ok2_read
	je ok2_read
	xor %ax,%ax
	sub %bx,%ax
	shr $9,%ax
ok2_read:
	call read_track
	mov %ax,%cx
	add sread,%ax
	cmp $sectors,%ax
	jne ok3_read
	mov $1,%ax
	sub head,%ax
	jne ok4_read
	###inc track
	push %bx
	mov track,%bx
	inc %bx
	mov %bx,track
	pop %bx
ok4_read:
	mov %ax,head
	xor %ax,%ax
ok3_read:
	mov %ax,sread
	shl $9,%cx
	add %cx,%bx
	jnc rp_read
	mov %es,%ax
	add $0x1000,%ax
	mov %ax,%es
	xor %bx,%bx
	jmp rp_read

read_track:
	push %ax
	push %bx
	push %cx
	push %dx
	mov track,%dx
	mov sread,%cx
	inc %cx
	mov %dl,%ch
	mov head,%dx
	mov %dl,%dh
	mov $0,%dl
	and $0x0100,%dx
	mov $2,%ah
	int $0x13
	jc bad_rt
	pop %dx
	pop %cx
	pop %bx
	pop %ax
	ret
bad_rt:	mov $0,%ax
	mov $0,%dx
	int $0x13
	pop %dx
	pop %cx
	pop %bx
	pop %ax
	jmp read_track

/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	push %dx
	mov $0x3f2,%dx
	mov $0,%al
	out %al,%dx
	pop %dx
	ret

gdt:
	.word	0,0,0,0		# dummy

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9A00		# code read/exec
	.word	0x00C0		# granularity=4096, 386

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9200		# data read/write
	.word	0x00C0		# granularity=4096, 386

idt_48:
	.word	0			# idt limit=0
	.word	0,0			# idt base=0L

gdt_48:
	.word	0x800		# gdt limit=2048, 256 GDT entries
	.word	gdt,0x9		# gdt base = 0X9xxxx
	
msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

.org 510
.word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:
