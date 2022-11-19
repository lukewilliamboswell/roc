interface Model
    exposes [
        Model,
    ]
    imports []

# This is a workaround to use glue. The Model should live in the app and be 
# supplied to the platform, but this isn't support by glue yet.

CursorPosition : {row: U16, col: U16}
Cursor : [Hidden, At CursorPosition]

Model : {
    text : Str,
    cursor : Cursor,
}
