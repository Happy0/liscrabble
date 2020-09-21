module Auth0 (auth0Provider) where

    import Prelude
    import Yesod.Auth.OAuth2.Prelude
    import qualified Data.Text as T
    
    instance FromJSON User where
        parseJSON = withObject "User" $ \o -> User <$> o .: "id"


    newtype User = User Int

    pluginName :: Text
    pluginName = "oauth0"

    auth0Provider :: YesodAuth m => Text -> Text -> AuthPlugin m
    auth0Provider clientId clientSecret =
        authOAuth2 pluginName oauth2 $ \manager token -> do
            (User userId, userResponse) <- authGetProfile
                pluginName
                manager
                token
                "https://api.github.com/user"

            pure Creds
                { credsPlugin = pluginName
                , credsIdent = T.pack $ show userId
                , credsExtra = setExtra token userResponse
                }
        where
            oauth2 = OAuth2
                { oauthClientId = clientId
                , oauthClientSecret = clientSecret
                , oauthOAuthorizeEndpoint = "https://mysite.com/oauth/authorize"
                , oauthAccessTokenEndpoint = "https://mysite.com/oauth/token"
                , oauthCallback = Nothing
                }