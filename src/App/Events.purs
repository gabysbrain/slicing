module App.Events where

import Prelude
import Loadable (Loadable(..))
import Pareto (paretoSet)
import App.Data (AppData, PointData, LineData, fromCsv)
import App.Routes (Route)
import App.State (State(..), FileLoadError(..))
import Control.Monad.Aff (Aff(), makeAff, attempt)
import Control.Monad.Eff (Eff())
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error)
import Control.Monad.Except (Except, except, throwError, runExcept, withExcept)
import Data.DataFrame as DF
import Data.Either (Either(..), either)
import Data.Foldable (foldMap)
import Data.Foreign (ForeignError(ForeignError), readString)
import Data.HTTP.Method (Method(GET))
import Data.List.NonEmpty as NEL
import Data.Maybe (Maybe(..))
import Data.Number as N
import Data.Nullable as Null
import Data.Set as Set
import DOM (DOM)
import DOM.Event.Types as EVT
import DOM.File.FileList (item)
import DOM.File.FileReader (fileReader, result, readAsText)
import DOM.File.Types (File, FileList, fileToBlob)
import Network.HTTP.Affjax (AJAX, get)
import Pux (EffModel, noEffects)
import Pux.DOM.Events (DOMEvent, targetValue)

data Event 
  = PageView Route
  | ParetoRadiusChange DOMEvent
  | LoadStaticFile String DOMEvent
  | DataFileChange DOMEvent
  | ReceiveData (Except FileLoadError AppData)
  | HoverParetoFront (Array LineData)
  | HoverParetoPoint (Array PointData)
  -- | StartParetoFilter AppData
  -- | FinishParetoFilter AppData

foreign import targetFileList :: DOMEvent -> FileList
foreign import readFileAsText :: forall e
                               . (String -> Eff e Unit)
                              -> File
                              -> Eff e Unit

type AppEffects fx = (ajax :: AJAX, dom :: DOM | fx)

foldp :: ∀ fx. Event -> State -> EffModel State Event (AppEffects fx)
foldp (PageView route) (State st) = noEffects $ State st { route = route, loaded = true }
foldp (ParetoRadiusChange ev) (State st) = noEffects $ 
  case N.fromString (targetValue ev) of
    Just r  -> State (st { paretoRadius = r })
    Nothing -> State st
foldp (ReceiveData d) (State st) = noEffects $ 
  State st { dataset = either Failed Loaded $ runExcept d }
foldp (LoadStaticFile fn _) (State st) =
  { state: State (st { dataset = Loading })
  , effects: [ do
      let url = "/test_data/" <> fn
      res <- (attempt $ get url)
      let ds = either (throwError <<< LoadError <<< NEL.singleton <<< ForeignError <<< show)
                      (\r -> parseCsv r.response) res
          --either (Left <<< LoadError) (\r -> parseCsv r.response) res
          --res.response >>= parseCsv
      pure $ Just $ ReceiveData $ DF.runQuery paretoSet <$> ds
    ]
  }
-- load the data from the file the user specified
foldp (DataFileChange ev) (State st) = 
  { state: State (st { dataset = Loading })
  , effects: [ do
      let f = userFile ev :: Except FileLoadError File
      raw <- readFile' f
      -- FIXME: maybe do the pareto calculatino in a separate async event
      let ds = raw >>= parseCsv
      pure $ Just $ ReceiveData $ DF.runQuery paretoSet <$> ds
    ]
  }
foldp (HoverParetoFront pfs) (State st) = noEffects $
  State st {selectedFronts=foldMap (\g -> Set.singleton g.groupId) pfs}
foldp (HoverParetoPoint pts) (State st) = noEffects $
  State st {selectedPoints=foldMap (\p -> Set.singleton p.rowId) pts}  

readFile :: forall eff. File -> Aff eff String
readFile f = makeAff (\error success -> readFileAsText success f)

readFile' :: forall eff. Except FileLoadError File -> Aff eff (Except FileLoadError String)
readFile' f = case runExcept f of
  Left err -> pure $ throwError err
  Right f' -> readFile'' f'

readFile'' :: forall eff. File -> Aff eff (Except FileLoadError String)
readFile'' f = do
  contents <- readFile f
  pure $ pure contents

userFile :: EVT.Event -> Except FileLoadError File
userFile ev = case Null.toMaybe $ item 0 fl of
    Nothing -> throwError NoFile
    Just f -> pure f
  where
  fl = targetFileList ev -- FIXME: replace with readFileList

parseCsv :: String -> (Except FileLoadError AppData)
parseCsv = withExcept ParseError <<< fromCsv

