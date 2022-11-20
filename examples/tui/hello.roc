app "hello"
    packages { pf: "platform/main.roc" }
    imports [
        pf.Model.{ Model },
        pf.Event.{ Event, Bounds },
        pf.Elem.{ Elem },
    ]
    provides [program] {} to pf

init : Bounds -> Model
init = \_ -> { 
    text: "Luke!",
    scroll : { row : 0, col : 0 },
}

update : Model, Event -> Model
update = \model, event ->
    when event is
        KeyPressed code ->
             when code is 
                 Left -> Model.updateScroll model Left
                 Right -> Model.updateScroll model Right
                 Up -> Model.updateScroll model Up
                 Down -> Model.updateScroll model Down
                 _ -> model
        _ ->
            model

# boundsToStr : Bounds -> Str 
# boundsToStr = \{height, width} ->
#     h = Num.toStr height
#     w = Num.toStr width
#     "Current Window H: \(h), W:\(w)"

noStyle = { bg: Default, fg: Default, modifiers: [] }

simpleBlockConfig = {
        title : "Hello World",
        titleAlignment : Center,
        style : noStyle,
        borders : [All],
        borderStyle : noStyle,
        borderType : Plain,
    }

paragraph = \scroll -> Paragraph {
    text : [
        { text : "Hello", style : {noStyle & fg: Blue} },
        { text : " ", style : noStyle },
        { text : "World", style : {noStyle & fg: Red } },
        { text : "!", style : noStyle },
        { text : loremIpsum1, style : noStyle },
        { text : loremIpsum2, style : noStyle },
        { text : loremIpsum3, style : noStyle },
        { text : loremIpsum4, style : noStyle },
        { text : loremIpsum5, style : noStyle },
    ],
    block : simpleBlockConfig,
    textAlignment : Left,
    scroll : scroll,
    cursor : Hidden,
}

render : Model -> List Elem
render = \model -> [paragraph model.scroll]

program = { init, update, render }

loremIpsum1 = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Massa vitae tortor condimentum lacinia quis. Tristique senectus et netus et malesuada fames ac. Magnis dis parturient montes nascetur ridiculus. Faucibus nisl tincidunt eget nullam. Velit euismod in pellentesque massa. Enim eu turpis egestas pretium aenean pharetra magna. Orci sagittis eu volutpat odio facilisis mauris sit. Ac tortor vitae purus faucibus ornare suspendisse sed nisi lacus. Aliquet nec ullamcorper sit amet risus nullam eget. Lectus proin nibh nisl condimentum id venenatis a condimentum vitae. Cursus metus aliquam eleifend mi in nulla posuere. A lacus vestibulum sed arcu. Nunc scelerisque viverra mauris in aliquam sem fringilla. Metus dictum at tempor commodo ullamcorper a lacus vestibulum."
loremIpsum2 = "Ullamcorper velit sed ullamcorper morbi tincidunt. Gravida neque convallis a cras. Pharetra sit amet aliquam id. Massa ultricies mi quis hendrerit. Faucibus ornare suspendisse sed nisi lacus sed viverra tellus in. Quam nulla porttitor massa id neque aliquam vestibulum morbi blandit. Risus in hendrerit gravida rutrum quisque non. Pellentesque habitant morbi tristique senectus. Ultricies mi quis hendrerit dolor magna eget. Egestas fringilla phasellus faucibus scelerisque. Iaculis eu non diam phasellus vestibulum lorem sed. Dictumst vestibulum rhoncus est pellentesque elit ullamcorper dignissim cras tincidunt. Turpis massa tincidunt dui ut ornare lectus sit. Facilisi morbi tempus iaculis urna id volutpat lacus. Vitae suscipit tellus mauris a diam maecenas. Leo integer malesuada nunc vel risus."
loremIpsum3 = "Malesuada pellentesque elit eget gravida cum sociis natoque penatibus et. Varius duis at consectetur lorem. Augue eget arcu dictum varius duis at consectetur lorem. Consequat ac felis donec et. Nunc eget lorem dolor sed viverra ipsum. Faucibus pulvinar elementum integer enim neque volutpat ac tincidunt vitae. Nisl suscipit adipiscing bibendum est ultricies integer quis. Id velit ut tortor pretium viverra suspendisse potenti nullam. Tortor pretium viverra suspendisse potenti nullam ac tortor. Elementum curabitur vitae nunc sed velit dignissim sodales. Arcu non sodales neque sodales ut etiam sit. Mauris pharetra et ultrices neque ornare aenean euismod elementum nisi. Nulla facilisi etiam dignissim diam quis enim lobortis. Turpis massa sed elementum tempus. Dictum varius duis at consectetur lorem donec massa. Suspendisse faucibus interdum posuere lorem ipsum dolor. A erat nam at lectus urna duis convallis convallis. Vitae congue eu consequat ac felis donec et. In fermentum et sollicitudin ac orci phasellus egestas tellus. Consectetur adipiscing elit pellentesque habitant morbi tristique."
loremIpsum4 = "Dictum fusce ut placerat orci nulla pellentesque dignissim. Vitae auctor eu augue ut lectus arcu bibendum at. A erat nam at lectus urna duis convallis convallis tellus. Non consectetur a erat nam. Lacus vestibulum sed arcu non odio euismod. Vitae tortor condimentum lacinia quis vel eros. Ac tincidunt vitae semper quis. Et egestas quis ipsum suspendisse ultrices gravida. A diam maecenas sed enim ut. Nunc sed id semper risus in hendrerit. Faucibus pulvinar elementum integer enim. Non arcu risus quis varius quam quisque id. Aliquam ultrices sagittis orci a scelerisque purus semper eget. Tincidunt tortor aliquam nulla facilisi cras fermentum odio eu feugiat. Vitae sapien pellentesque habitant morbi tristique senectus et netus et. Mauris in aliquam sem fringilla ut. Mauris ultrices eros in cursus turpis massa tincidunt."
loremIpsum5 = "Enim neque volutpat ac tincidunt vitae. Quisque sagittis purus sit amet volutpat consequat. In eu mi bibendum neque egestas congue quisque. Amet est placerat in egestas. Arcu vitae elementum curabitur vitae nunc sed velit. Sed lectus vestibulum mattis ullamcorper. Pellentesque pulvinar pellentesque habitant morbi. Tincidunt vitae semper quis lectus nulla at volutpat diam ut. Sed lectus vestibulum mattis ullamcorper velit sed ullamcorper morbi tincidunt. At in tellus integer feugiat scelerisque varius morbi enim. Mollis aliquam ut porttitor leo a."