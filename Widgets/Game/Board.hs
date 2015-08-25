module Widgets.Game.Board (initialBoard, boardWidget) where

    import Import
    import Wordify.Rules.Board
    import Wordify.Rules.Pos
    import Wordify.Rules.Square
    import Wordify.Rules.Tile
    import Data.List
    import Data.List.Split

    {- TODO: Style / deal with blank letter tiles -}

    boardWidget :: Board -> Widget
    boardWidget board = 
        do
            [whamlet|
                <div .board_wrap>
                    <div .board>
                        $forall row <- rows
                            ^{templateRow row}
            |]
            toWidget
                [cassius|
                    .board_wrap
                        width: #{boardWidth}px
                        height: #{boardWidth}px
                        border: 1px solid #d5c3a2
                        border-radius: 5px
                        margin-bottom: 40px
                        position: relative

                    .board
                        width: #{boardWidth}px
                        height: #{boardWidth}px
                        border-radius: 5px

                    .square
                        border: 1px solid #d5c3a2
                        position: absolute
                        width: #{tileWidth}px
                        height: #{tileWidth}px
                        text-align: center
                        font-size: 8px
                        display: block

                    .specialtext
                        position: absolute
                        top: 10px
                        left: 8px

                    .square.normal
                        background-color: #e8ddc7

                    .square.doubleletter
                        background-color: #3ef

                    .square.tripleletter
                        background-color: #77f

                    .square.doubleword
                        background-color: #f9b

                    .square.tripleword
                        background-color: #f55
                |]
        where
            rows = layoutBoard board
            width = 32 :: Int
            tileWidth = show $ (width :: Int)
            boardWidth = show $ width * 15

    templateRow row = [whamlet|
        $forall square <- row
            ^{templateSquare square}
     |]

    templateSquare (pos, square) =
        do
            addScript $ StaticR js_util_js
            [whamlet|
                    <div class="square #{squareClass}" data-x=#{xPos pos} data-y=#{yPos pos} style="top:#{xPosition}px; left:#{yPosition}px;">
                        $maybe tile <- tileIfOccupied square
                            ^{templateTile tile}
            |]
            toWidget
                [julius|
                    $(".square").droppable({accept: ".tile", 
                        drop: function( event, ui ) {
                          // When dropped, the element is not attached to the DOM element. Instead, its position is changed relative to where it
                          // was originally. We manually attach it to the DOM element. When subsequently dragged, it seems to go under the board,
                          // so we set a z-index
                          ui.draggable.detach().appendTo(this);
                          ui.draggable.attr("style", "position: relative; left: 0px; top: 0px; z-index: 10;");
                        },
                        out: function(event, ui) {

                        }
                    });

                    var disableDraggadleSquares = function() {
                        $(".square").children(".tile").draggable('disable');
                    }

                    util.addWindowLoadEventTask(disableDraggadleSquares);

                |]
        where
            xPosition = (xPos pos -1) * 32
            yPosition = (yPos pos -1) * 32

            (squareClass, squareText) = case square of
                DoubleLetter(_) -> ("doubleletter" :: Text, "DL" :: Text)
                TripleLetter(_) -> ("tripleletter", "TL")
                DoubleWord(_) -> ("doubleword", "DW")
                TripleWord(_) -> ("tripleword", "TW")
                Normal(_) -> ("normal", "")

    initialBoard :: Widget
    initialBoard = boardWidget emptyBoard

    templateTile tile = $(widgetFile "tile")

    {- Layout the board in rows of 15 from (1,1) -> (15,15) -}
    layoutBoard :: Board -> [[(Pos, Square)]]
    layoutBoard = transpose . chunksOf 15 . allSquares