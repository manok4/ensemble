# Bug: truncate keeps one word too few

`truncate('a b c d', 3)` returns `a b`. It should return `a b c`: `max_tokens` is the number of words to keep.
