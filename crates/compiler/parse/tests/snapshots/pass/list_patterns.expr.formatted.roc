when [] is
    [] -> {}
    [..] -> {}
    [_, .., _, ..] -> {}
    [a, b, c, d] -> {}
    [a, b, ..] -> {}
    [.., c, d] -> {}
    [[A], [..], [a]] -> {}
    [[[], []], [[], x]] -> {}