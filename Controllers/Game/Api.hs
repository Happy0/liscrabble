module Controllers.Game.Api (ClientMessage(ChatMessage),
                             GameMessage,
                             ServerResponse(PlayerSaid, InvalidCommand)) where

    import Data.Aeson
    import Data.Aeson.Types
    import Control.Applicative
    import Data.Text
    import Prelude
    import qualified Data.HashMap.Strict as HM
    import Model.Api
    import Wordify.Rules.Board
    import Wordify.Rules.Pos
    import Wordify.Rules.Tile
    import Wordify.Rules.Square
    import qualified Data.List as L

    data ClientMessage = ChatMessage Text

    data ServerResponse = PlayerSaid Text Text | InvalidCommand Text

    data GameMessage

    instance FromJSON ClientMessage where
        parseJSON (Object request) =
            case HM.lookup "command" request of
                Just (String command) ->
                    request .: "payload" >>= parseCommand command
                _ -> error "Expected command to have text value"

        parseJSON _ = error "Invalid JSON"

    instance ToJSON ServerResponse where
        toJSON (PlayerSaid name message) = object ["name" .= name, "message" .= message]
        toJSON (InvalidCommand msg) = object ["error" .= msg]

    instance ServerMessage ServerResponse where
        commandName (PlayerSaid _ _) = "said"
        commandName (InvalidCommand _) = "error"

    parseCommand :: Text -> Value -> Parser ClientMessage
    parseCommand "say" value = parseChatMessage value
    parseCommand "boardMove" value = parseBoardMove value
    parseCommand _ _ = error "Unrecognised command"

    parseChatMessage :: Value -> Parser ClientMessage
    parseChatMessage (Object object) = ChatMessage <$> object .: "message"
    parseChatMessage _ = error "Unrecognised chat message"

    parseBoardMove :: Value -> Parser ClientMessage
    parseBoardMove (Array a) = undefined
    parseBoardMove _ = error "A board move should have an array as its payload"

    instance ToJSON Board where
        toJSON = toJSON . groupSquaresByColumn . allSquares

    instance ToJSON Square where
        toJSON (Normal tile) = object ["tile" .= tile, "bonus" .= ("N" :: Text)]
        toJSON (DoubleLetter tile) = object ["tile" .= tile, "bonus" .= ("DL" :: Text)]
        toJSON (TripleLetter tile) = object ["tile" .= tile, "bonus" .= ("TL" :: Text)]
        toJSON (DoubleWord tile) = object ["tile" .= tile, "bonus" .= ("DW" :: Text)]
        toJSON (TripleWord tile) = object ["tile" .= tile, "bonus" .= ("TW" :: Text)]

    instance ToJSON Tile where
        toJSON (Letter letter value) = object ["letter" .= letter, "value" .= value]
        toJSON (Blank (Just letter)) = object ["letter" .= letter, "value" .= (0 :: Int)]
        toJSON _ = object ["letter" .= '_', "value" .= (0 :: Int)]

    instance FromJSON Pos where
        parseJSON value = undefined

    instance FromJSON Tile where
        parseJSON value = undefined

    groupSquaresByColumn :: [(Pos, Square)] -> [[Square]]
    groupSquaresByColumn squares = 
        let columns = L.groupBy sameColumn squares
        in (Prelude.map . Prelude.map) snd columns
        where
            sameColumn square1 square2 = xPos (fst square1) == xPos (fst square2)


