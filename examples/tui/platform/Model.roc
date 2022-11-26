interface Model
    exposes [
        Model,
        updateScroll,
    ]
    imports []

# This is a workaround to use glue. The Model should live in the app and be 
# supplied to the platform, but this isn't support by glue yet.

Model : {
    text : Str,
    scroll : { row : U16, col : U16 },
}

updateScroll : Model, [Up, Down, Left, Right] -> Model
updateScroll = \model, direction ->
    col = when direction is 
        Up -> model.scroll.col
        Down -> model.scroll.col
        Left -> Num.subWrap model.scroll.col 1u16
        Right -> Num.addWrap model.scroll.col 1u16

    row = when direction is 
        Up -> Num.subWrap model.scroll.row 1u16
        Down -> Num.addWrap model.scroll.row 1u16
        Left -> model.scroll.row
        Right -> model.scroll.row

    {model & scroll : {col : col, row : row }}