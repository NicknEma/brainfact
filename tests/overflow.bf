[ This program is used to test memory-cell overflow.

  Starting from 4, a loop goes forward by 4, each time
  incrementing a separate counter by 1.
  This is effectively doing 256 / 4, which is the
  ascii character for '@'.
  
  The '@' is then printed, followed by a newline.
]

> + < ++++ [ > + < ++++ ] > .  Cell c1 = '@' (result of 256 / 4) and print
> +++++ +++++ .                Cell c2 = 10 (line feed) and print
