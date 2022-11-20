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
    scroll = when direction is 
        Up -> {col : model.scroll.col, row : Num.subWrap model.scroll.row 1 }
        Down -> {col : model.scroll.col, row : Num.addWrap model.scroll.row 1 }
        Left -> {row : model.scroll.row, col : Num.subWrap model.scroll.col 1 }
        Right -> {row : model.scroll.row, col : Num.addWrap model.scroll.col 1 }

    {model & scroll : scroll}