a = [1, 'hi', 3.14, 1, 2, [4, 5]]

a[2]             # => 3.14
a.[](2)          # => 3.14
a.reverse        # => [[4, 5], 2, 1, 3.14, 'hi', 1]
a.flatten.uniq   # => [1, 'hi', 3.14, 2, 4, 5]
