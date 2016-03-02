{-# LANGUAGE FlexibleContexts #-}
module File.Format.TNT.Partitioning where

import           File.Format.TNT.Command.CCode
import           File.Format.TNT.Command.CNames
import           File.Format.TNT.Command.Cost
import           File.Format.TNT.Command.Procedure
import           File.Format.TNT.Command.TRead
import           File.Format.TNT.Command.XRead
import           File.Format.TNT.Internal
import           Text.Megaparsec
import           Text.Megaparsec.Custom
import           Text.Megaparsec.Prim (MonadParsec)

data Part
   = CC CCode
   | CN CNames
   | CO Cost
   | TR TRead 
   | XR XRead
   | Ignore

type Commands = ([CCode],[CNames],[Cost],[TRead],[XRead])

gatherCommands :: MonadParsec s m Char => m Commands
gatherCommands = partition <$> many commands
  where
    commands  = choice
              [ CC     <$> ccodeCommand
              , CN     <$> cnamesCommand
              , CO     <$> costCommand
              , TR     <$> treadCommand
              , XR     <$> xreadCommand
              , Ignore <$  procedureCommand
              , Ignore <$  ignoredCommand
              ]
    partition = foldr f ([],[],[],[],[])
      where
        f (CC e) (v,w,x,y,z) = (e:v,  w,  x,  y,  z)
        f (CN e) (v,w,x,y,z) = (  v,e:w,  x,  y,  z)
        f (CO e) (v,w,x,y,z) = (  v,  w,e:x,  y,  z)
        f (TR e) (v,w,x,y,z) = (  v,  w,  x,e:y,  z)
        f (XR e) (v,w,x,y,z) = (  v,  w,  x,  y,e:z)
        f Ignore x           = x

ignoredCommand :: MonadParsec s m Char => m String
ignoredCommand = commandKeyword <* commandBody <* symbol terminal
  where
    commandKeyword = somethingTill inlineSpaceChar
    commandBody    = trim $ somethingTill terminal
    terminal       = char ';'
