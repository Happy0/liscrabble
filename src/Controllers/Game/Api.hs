module Controllers.Game.Api (
                             ChatMessage(ChatMessage),
                             ClientMessage(AskPotentialScore, SendChatMessage, BoardMove, ExchangeMove, PassMove),
                             GameMessage(PlayerBoardMove, GameEnd, PlayerPassMove, PlayerExchangeMove, PlayerChat, GameIdle),
                             ServerResponse(PotentialScore, BoardMoveSuccess, ExchangeMoveSuccess,
                                PassMoveSuccess, ChatSuccess, InitialiseGame, InvalidCommand), MoveSummary(BoardMoveSummary, PassMoveSummary, ExchangeMoveSummary), toMoveSummary, transitionToMessage, transitionToSummary) where

    import Data.Aeson
    import Data.Aeson.Types
    import qualified Data.Vector as V
    import Control.Applicative
    import qualified Data.Map as M
    import Data.Text
    import qualified Data.Maybe as Mb
    import Prelude
    import qualified Data.HashMap.Strict as HM
    import Model.Api
    import Wordify.Rules.Board
    import Wordify.Rules.FormedWord
    import qualified Wordify.Rules.Game as G
    import Wordify.Rules.LetterBag
    import Wordify.Rules.Move
    import Wordify.Rules.Player
    import Wordify.Rules.Pos
    import Wordify.Rules.Tile
    import Wordify.Rules.Square
    import qualified Data.List as L

    data ChatMessage = ChatMessage {user :: Text, message :: Text}

    data MoveSummary = BoardMoveSummary {overallScore :: Int,
                                         wordsAndScores :: [(Text, Int)],
                                         moveDirection :: Direction,
                                         placedTiles :: [Pos]} |
                       PassMoveSummary |
                       ExchangeMoveSummary |
                       GameEndSummary (Maybe [(Text, Int)]) [Player]

    data ClientMessage = AskPotentialScore [(Pos, Tile)] |
                         SendChatMessage Text |
                         BoardMove [(Pos, Tile)] |
                         ExchangeMove [Tile] |
                         PassMove

    {-
       Messages sent directly from the server to a client request over the websocket.
       The messages are not broadcasted to all clients.
    -}

    data ServerResponse = InitialiseGame [GameMessage] (Maybe [Tile]) [Player] (Maybe Int) Int Int |
                          PotentialScore Int |
                          BoardMoveSuccess [Tile] |
                          ExchangeMoveSuccess [Tile] |
                          PassMoveSuccess |
                          ChatSuccess |
                          InvalidCommand Text

    -- Messages sent over the server game channel to notify clients of changes
    -- such as a player making a move successfully
    data GameMessage = PlayerBoardMove {moveNumber :: Int,
                                        placed :: [(Pos, Tile)],
                                        summary :: MoveSummary,
                                        players :: [Player],
                                         nowPlaying :: Int,
                                        tilesRemaining :: Int} |
                                     GameEnd Int (Maybe [(Pos, Tile)]) MoveSummary |
                                     PlayerPassMove Int Int MoveSummary |
                                     PlayerExchangeMove Int Int [Tile] MoveSummary |
                                     PlayerChat ChatMessage |
                                     GameIdle

    instance ToJSON ChatMessage where
        toJSON (ChatMessage user message) = object ["player" .= user, "message" .= message]

    toWord :: Direction -> Text
    toWord Horizontal = "horizontal"
    toWord Vertical = "vertical"

    instance ToJSON MoveSummary where
        toJSON (BoardMoveSummary overallScore wordsWithScores direction placed) =
           object ["overallScore" .= overallScore,
                   "direction" .= toWord direction,
                   "placed" .= fmap toJSON placed,
                   "wordsMade" .= fmap wordSummaryJSON wordsWithScores,
                   "type" .= boardSummaryType]
        toJSON (PassMoveSummary) = object ["type" .= passSummaryType]
        toJSON (ExchangeMoveSummary) = object ["type" .= exchangeSummaryType]
        toJSON (GameEndSummary maybeWords players) =
            object ["type" .= gameEndSummaryType,
                    "players" .= players,
                    "lastMoveScore" .= (fmap sum $ (fmap . fmap) snd maybeWords),
                    "wordsMade" .=
                        case
                            maybeWords of
                                Nothing -> []
                                Just wordsWithScores -> fmap wordSummaryJSON wordsWithScores]

    wordSummaryJSON (word, score) = object ["word" .= word, "score" .= score]
    boardSummaryType = ("board" :: Text)
    passSummaryType = ("pass" :: Text)
    exchangeSummaryType = ("exchange" :: Text)
    gameEndSummaryType = ("gameEnd" :: Text)

    instance ServerMessage GameMessage where
        commandName PlayerBoardMove{}  = "playerBoardMove"
        commandName (PlayerPassMove {}) = "playerPassMove"
        commandName (PlayerExchangeMove {}) = "playerExchangeMove"
        commandName (GameEnd {}) = "gameFinished"
        commandName (PlayerChat {}) = "playerChat"
        commandName (GameIdle {}) = "gameIdle"

    instance ToJSON GameMessage where
        toJSON (PlayerBoardMove moveNumber placed summary players nowPlaying tilesRemaining) =
            object ["moveNumber" .= moveNumber,
                    "placed" .= fmap writePosAndTile placed,
                    "summary" .= toJSON summary,
                    "players" .= toJSON players,
                    "nowPlaying" .= nowPlaying,
                    "tilesRemaining" .= tilesRemaining]
        toJSON (GameEnd moveNumber maybePlaced summary) =
             object ["moveNumber" .= moveNumber,
                    "placed" .= (fmap . fmap) writePosAndTile maybePlaced,
                    "summary" .= summary]
        toJSON (PlayerExchangeMove moveNumber nowPlaying _ summary) =
            -- We do not tell clients what tiles the player exchanged
            object ["moveNumber" .= moveNumber, "nowPlaying" .= nowPlaying, "summary" .= summary]
        toJSON (PlayerPassMove moveNumber nowPlaying summary) =
            object ["moveNumber" .= moveNumber, "nowPlaying" .= nowPlaying, "summary" .= summary]
        toJSON (PlayerChat chatMessage) = toJSON chatMessage
        toJSON (GameIdle) = object []

    instance FromJSON ClientMessage where
        parseJSON (Object request) =
            case HM.lookup "command" request of
                Just (String command) ->
                    request .: "payload" >>= parseCommand command
                _ -> fail "Expected command to have text value"

        parseJSON _ = fail "Invalid JSON"

    instance ToJSON ServerResponse where
        toJSON (BoardMoveSuccess tiles) = object ["rack" .= toJSON tiles]
        toJSON PassMoveSuccess = object []
        toJSON (ExchangeMoveSuccess tiles) = object ["rack" .= toJSON tiles]
        toJSON (ChatSuccess) = object []
        toJSON (InvalidCommand msg) = object ["error" .= msg]
        toJSON (PotentialScore score) = object ["potentialScore" .= score]
        toJSON (InitialiseGame moves rack players playerNumber toMove tilesRemaining) =
            object [
                   "moveCommands" .= (fmap toJSONMessage moves),
                   "rack" .= rack, "players" .= players,
                   "playerNumber" .= playerNumber, "playerMove" .= toMove,
                   "tilesRemaining" .= tilesRemaining]

    instance ServerMessage ServerResponse where
        commandName (BoardMoveSuccess _) = "boardMoveSuccess"
        commandName (ExchangeMoveSuccess _) = "exchangeMoveSuccess"
        commandName PassMoveSuccess = "passMoveSuccess"
        commandName ChatSuccess = "chatSuccess"
        commandName (PotentialScore _) = "potentialScore"
        commandName (InvalidCommand _) = "error"
        commandName (InitialiseGame {}) = "initialise"

    writePosAndTile :: (Pos, Tile) -> Value
    writePosAndTile (pos, tile) = object ["pos" .= toJSON pos, "tile" .= toJSON tile]

    parseCommand :: Text -> Value -> Parser ClientMessage
    parseCommand "say" value = parseChatMessage value
    parseCommand "potentialScore" value = parsePotentialScore value
    parseCommand "boardMove" value = parseBoardMove value
    parseCommand "exchangeMove" value = parseExchangeMove value
    parseCommand "passMove" _ = return PassMove
    parseCommand _ _ = fail "Unrecognised command"

    parseChatMessage :: Value -> Parser ClientMessage
    parseChatMessage (Object object) = SendChatMessage <$> object .: "message"
    parseChatMessage _ = fail "Unrecognised chat message"

    parsePotentialScore :: Value -> Parser ClientMessage
    parsePotentialScore (Array a) = AskPotentialScore <$> (sequence . V.toList $ fmap getPosAndTile a)
    parsePotentialScore _ = fail "Unexpected payload for 'potentialScore'"

    parseBoardMove :: Value -> Parser ClientMessage
    parseBoardMove (Array a) = BoardMove <$> (sequence . V.toList $ fmap getPosAndTile a)
    parseBoardMove _ = fail "A board move should have an array as its payload"

    parseExchangeMove :: Value -> Parser ClientMessage
    parseExchangeMove (Array a) = ExchangeMove <$> (sequence . V.toList $ fmap parseJSON a)
    parseExchangeMove _ = fail "An exchange move should have an array of tiles as its payload"

    getPosAndTile :: Value -> Parser (Pos, Tile)
    getPosAndTile (Object val) =
        do
            pos <-  val .: "pos" >>= parseJSON
            tile <-  val .: "tile" >>= parseJSON
            return (pos, tile)
    getPosAndTile _ = fail "expected object payload with pos and tile"

    transitionToMessage :: GameTransition -> GameMessage
    transitionToMessage et@(ExchangeTransition newGameState beforeExchange afterExchange) =
         PlayerExchangeMove
            (G.moveNumber newGameState)
            (G.playerNumber newGameState)
            (tilesOnRack beforeExchange L.\\ tilesOnRack afterExchange)
            (transitionToSummary et)
    transitionToMessage pt@(MoveTransition _ newGame wordsFormed) =
        PlayerBoardMove
            (G.moveNumber newGame)
            (Mb.mapMaybe (\(pos, square) ->
                (pos,) <$> (tileIfOccupied square)) $ playerPlaced wordsFormed)
            (transitionToSummary pt)
            (G.players newGame)
            (G.playerNumber newGame)
            ((bagSize . G.bag) newGame)
    transitionToMessage passTransition@(PassTransition newGame) =
        PlayerPassMove (G.moveNumber newGame)
                       (G.playerNumber newGame)
                       (transitionToSummary passTransition)
    transitionToMessage gf@(GameFinished game maybeWords) =
        GameEnd (G.moveNumber game) lastPlaced (transitionToSummary gf)
        where
            movesMade = G.movesMade game
            lastMove = L.last movesMade
            lastPlaced = case lastMove of
                PlaceTiles tiles -> Just $ M.toList tiles
                _ -> Nothing


    transitionToSummary :: GameTransition -> MoveSummary
    transitionToSummary (MoveTransition player game formed) = toMoveSummary formed
    transitionToSummary (PassTransition _) = PassMoveSummary
    transitionToSummary (ExchangeTransition _ _ _ ) = ExchangeMoveSummary
    transitionToSummary (GameFinished game maybeWords) =
          GameEndSummary ((toTextScores . snd . wordsWithScores) <$> maybeWords) (G.players game)
        where
            getPenalty before after = (score after - score before)

    toMoveSummary :: FormedWords -> MoveSummary
    toMoveSummary formedWords =
        let (overallScore, wordsAndScores) = wordsWithScores formedWords
        in let maybeDirection = direction (fst $ M.findMin (playerPlacedMap formedWords)) (fst $ M.findMax (playerPlacedMap formedWords))
        in let direction = maybe Horizontal id maybeDirection -- Default to Horizontal
        in (BoardMoveSummary
              overallScore
              (toTextScores wordsAndScores)
              direction
              (M.keys (playerPlacedMap formedWords)))

    toTextScores = fmap (\(word, score) -> (pack word, score))

    instance ToJSON Board where
        toJSON = toJSON . groupSquaresByColumn . allSquares

    instance ToJSON Square where
        toJSON (Normal tile) = object ["tile" .= tile, "bonus" .= ("N" :: Text)]
        toJSON (DoubleLetter tile) = object ["tile" .= tile, "bonus" .= ("DL" :: Text)]
        toJSON (TripleLetter tile) = object ["tile" .= tile, "bonus" .= ("TL" :: Text)]
        toJSON (DoubleWord tile) = object ["tile" .= tile, "bonus" .= ("DW" :: Text)]
        toJSON (TripleWord tile) = object ["tile" .= tile, "bonus" .= ("TW" :: Text)]

    instance ToJSON Player where
        toJSON player = object ["name" .= name player,
                                "score" .= score player,
                                "endBonus" .= endBonus player]

    instance ToJSON Tile where
        toJSON (Letter letter value) = object ["letter" .= letter, "value" .= value]
        toJSON (Blank (Just letter)) = object ["letter" .= letter, "value" .= (0 :: Int)]
        toJSON _ = object ["letter" .= '_', "value" .= (0 :: Int)]

    instance FromJSON Pos where
        parseJSON (Object value) = do
            x <- value .: "x"
            y <- value .:"y"
            let pos = posAt(x,y)
            case pos of
                Nothing -> fail "Position is not in valid board coordinate boundaries"
                Just p -> return p
        parseJSON _ = fail "Position must be a JSON object value, rather than an array, etc"

    instance ToJSON Pos where
        toJSON pos = object ["x" .= xPos pos, "y" .= yPos pos]

    instance FromJSON Tile where
        parseJSON (Object value) = do
            letter <- value .: "letter"
            tileValue <- value .: "value"

            return $
                 case tileValue of
                        0 -> case letter of
                                '_' -> Blank Nothing
                                chr -> Blank (Just chr)
                        x -> Letter letter tileValue
        parseJSON _ = fail "Tile must be a JSON object value, rather than an array, etc"

    groupSquaresByColumn :: [(Pos, Square)] -> [[Square]]
    groupSquaresByColumn squares =
        let columns = L.groupBy sameColumn squares
        in (Prelude.map . Prelude.map) snd columns
        where
            sameColumn square1 square2 = xPos (fst square1) == xPos (fst square2)
