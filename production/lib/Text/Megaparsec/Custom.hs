{-# LANGUAGE FlexibleContexts #-}

module Text.Megaparsec.Custom
 ( (<:>)
 , (<++>)
 , anyTill
 , double
 , endOfLine
 , fails
 , inlineSpace 
 , inlineSpaces
 ) where

import Data.Char             (isSpace)
import Text.Megaparsec
import Text.Megaparsec.Prim  (MonadParsec)
import Text.Megaparsec.Lexer (float,integer,signed)

(<:>) :: Applicative f => f a -> f [a] -> f [a]
(<:>) a b = (:)  <$> a <*> b

(<++>) :: Applicative f => f [a] -> f [a] -> f [a]
(<++>) a b = (++) <$> a <*> b

anyTill :: MonadParsec s m Char => m a -> m String
anyTill c = do 
    ahead <- optional $ lookAhead c
    case ahead of
      Just _  -> pure []
      Nothing -> anyChar <:> anyTill c

double :: MonadParsec s m Char => m Double
double = try (signed space float)
     <|> fromIntegral <$> (signed space integer)

endOfLine :: MonadParsec s m Char => m Char
endOfLine = (try eol <|> string "\r") *> pure '\n'

fails :: MonadParsec s m Char => [String] -> m a
fails []  = fail "Unspecified error" -- You were dumb
fails [x] = fail x
fails xs  = fail . init $ unlines xs

inlineSpace :: MonadParsec s m Char => m Char
inlineSpace = satisfy $ \x -> isSpace x 
                           && '\n' /= x
                           && '\r' /= x

inlineSpaces :: MonadParsec s m Char => m ()
inlineSpaces = skipMany inlineSpace

