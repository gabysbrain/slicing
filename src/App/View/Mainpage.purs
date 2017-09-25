module App.View.Mainpage where

import Prelude hiding (div, max, min)
import Math (sqrt)
import App.Data (FieldNames, formatNum)
import App.Events (Event(DataFileChange))
import App.State (State(..), DataInfo, FileLoadError(..))
import App.View.ParetoSlices as PS
import Data.Array as A
import Data.Traversable (for_)
import Data.Tuple (Tuple(..))
import Pux.DOM.HTML (HTML)
import Pux.DOM.Events (DOMEvent, onChange, onClick)
import Text.Smolder.HTML (div, label, h2, ul, li, p, a, select, option)
import Text.Smolder.HTML.Attributes (className, value)
import Text.Smolder.Markup ((!), (#!), text)
import Loadable (Loadable(..))
import Data.DataFrame as DF
import Data.Int (toNumber)

datasets = 
  [ Tuple "sphere" "sphere_3d.json"
  , Tuple "5D sphere" "sphere_5d.json"
  , Tuple "Klein bottle" "klein.json"
  ]

view :: State -> HTML Event
view (State st) =
  div do
    viewOptions
    viewSlices st.dataset

viewOptions :: HTML Event
viewOptions = div ! className "view-options" $ do
  label $ do
    text "Dataset:"
    select #! onChange DataFileChange $ do
      for_ datasets $ \(Tuple lbl url) ->
        option ! value url $ text lbl

viewSlices :: forall d. Loadable FileLoadError (DataInfo d) -> HTML Event
viewSlices Unloaded = div $ text "Nothing yet!"
viewSlices Loading = div $ text "Loading..."
viewSlices (Failed errs) = viewFileErrors errs
viewSlices (Loaded dsi) = PS.view dsi

viewFileErrors :: FileLoadError -> HTML Event
viewFileErrors NoFile = div $ text "" -- FIXME: should be empty
viewFileErrors (LoadError err) = 
  div do
    p $ text "cannot load file"
    ul ! className "details" $ do
      li $ text err

