interface Elem
    exposes [
        Elem,
        Color,
        TextModifier,
        BorderModifier,
        BorderType,
        Alignment,
        ScrollOffset,
        Style,
        LayoutDirection,
        Constraint,
        CursorPosition,
        Cursor,
        Corner,
        Span,
        ListConfig,
        BlockConfig,
        ParagraphConfig,
        LayoutConfig,
        PopupConfig,
    ]
    imports []

# TODO roc glue can't support more elements in this recusrive tage here yet
Elem : [
    Block BlockConfig,
    Paragraph ParagraphConfig,
    ListItems ListConfig,
    Layout (List Elem) LayoutConfig,
]

Color : [Rgb U8 U8 U8, Default, White, Black, Red, Green, Blue]
TextModifier : [Bold, Dim, Italic, Underlined, SlowBlink, RapidBlink, Reversed, Hidden, CrossedOut]
BorderModifier : [None, Top, Right, Bottom, Left, All]
BorderType : [Plain, Rounded, Double, Thick]
Alignment : [Left, Center, Right]
ScrollOffset : { row : U16, col : U16 }
Style : { fg : Color, bg : Color, modifiers : List TextModifier }
LayoutDirection : [Horizontal, Vertical]
Constraint : [Percentage U16, Ratio U32 U32, Length U16, Max U16, Min U16]
CursorPosition : { row : U16, col : U16 }
Cursor : [Hidden, At CursorPosition]
Corner : [TopLeft, TopRight, BottomRight, BottomLeft]
ModalPosition : { percentX : U16, percentY : U16 }
PopupConfig : [Default, Centered ModalPosition]

# Base widget to be used with all upper level ones.
# It may be used to display a box border around the widget and/or add a title.
BlockConfig : {
    title : Str,
    titleAlignment : Alignment,
    style : Style,
    borders : List BorderModifier,
    borderStyle : Style,
    borderType : BorderType,
}

# A single line string where all graphemes have the same style
Span : { text : Str, style : Style }

# A widget to display some text
ParagraphConfig : {
    text : List Span,
    block : BlockConfig,
    textAlignment : Alignment,
    scroll : ScrollOffset,
    cursor : Cursor,
}

# Use cassowary-rs solver to split area into smaller ones based on the preferred
# widths or heights and the direction.
LayoutConfig : {
    constraints : List Constraint,
    direction : LayoutDirection,
    vMargin : U16,
    hMargin : U16,
    popup : PopupConfig,
}

# A widget to display several items among which one can be selected (optional)
ListConfig : {
    items : List Span,
    block : BlockConfig,
    style : Style,
    highlightSymbol : Str,
    highlightSymbolRepeat : Bool,
    highlightStyle : Style,
    startCorner : Corner,
}
