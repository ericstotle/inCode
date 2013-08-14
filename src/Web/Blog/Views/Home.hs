{-# LANGUAGE OverloadedStrings #-}

module Web.Blog.Views.Home (viewHome) where

import Control.Applicative                   ((<$>))
import Control.Monad.Reader
import Text.Blaze.Html5                      ((!))
import Web.Blog.Models
import Web.Blog.Models.Util
import Web.Blog.Render
import Web.Blog.SiteData
import Web.Blog.Types
import Web.Blog.Util                         (renderFriendlyTime, renderDatetimeTime)
import Web.Blog.Views.Copy
import qualified Data.Foldable               as Fo
import qualified Data.Map                    as M
import qualified Data.Text                   as T
import qualified Database.Persist.Postgresql as D
import qualified Text.Blaze.Html5            as H
import qualified Text.Blaze.Html5.Attributes as A
import qualified Text.Blaze.Internal         as I

viewHome :: [(D.Entity Entry,(T.Text,[Tag]))] -> Int -> SiteRender H.Html
viewHome eList pageNum = do
  pageDataMap' <- pageDataMap <$> ask
  bannerCopy <- viewCopyFile (siteDataTitle siteData) "copy/static/home-banner.md"
  sidebarHtml <- viewSidebar
  homeUrl <- renderUrl "/"

  return $ 
    H.section ! A.class_ "home-section" ! mainSection $ do

      H.header ! A.class_ "tile unit span-grid" $ 
        H.section ! A.class_ "home-banner" $
          if pageNum == 1
            then
              bannerCopy
            else
              H.h1 ! A.class_ "home-banner-history" $
                H.a ! A.href (I.textValue homeUrl) $
                  H.toHtml $ siteDataTitle siteData

      H.nav ! A.class_ "tile unit one-of-four home-sidebar" $
        sidebarHtml

      H.div ! A.class_ "unit three-of-four" $ do
        H.div ! A.class_ "tile" $
          H.h2 ! A.class_ "recent-header" $ do
            "Recent Entries" :: H.Html
            when (pageNum > 1) $ do
              " (Page " :: H.Html
              H.toHtml pageNum
              ")" :: H.Html


        H.ul $
          forM_ eList $ \eData -> do
            let
              (D.Entity _ e,(u,ts)) = eData
              commentUrl = T.append u "#disqus_thread"

            H.li $
              H.article ! A.class_ "tile" $ do

                H.header $ do
                  H.time
                    ! A.datetime (I.textValue $ T.pack $ renderDatetimeTime $ entryPostedAt e)
                    ! A.pubdate "" 
                    ! A.class_ "pubdate"
                    $ H.toHtml $ renderFriendlyTime $ entryPostedAt e

                  H.h3 $ 
                    H.a ! A.href (I.textValue u) $
                      H.toHtml $ entryTitle e


                H.div ! A.class_ "entry-lede copy-content" $ do
                  entryLedeHtml e
                  H.p $ do
                    H.a ! A.href (I.textValue u) ! A.class_ "link-readmore" $
                      "Read more..."
                    " " :: H.Html
                    H.a ! A.href (I.textValue commentUrl) ! A.class_ "link-comment" $
                      "Comments"

                H.footer $
                  H.ul ! A.class_ "tag-list" $
                    forM_ ts $ \t ->
                      tagLi t


        H.footer ! A.class_ "tile home-footer" $ 

          H.nav $ do
            H.ul $ do

              Fo.forM_ (M.lookup "nextPage" pageDataMap') $ \nlink ->
                H.li ! A.class_ "home-next" $
                  H.a ! A.href (I.textValue nlink) $
                    H.preEscapedToHtml ("&larr; Older" :: T.Text)

              Fo.forM_ (M.lookup "prevPage" pageDataMap') $ \plink ->
                H.li ! A.class_ "home-prev" $
                  H.a ! A.href (I.textValue plink) $
                    H.preEscapedToHtml ("Newer &rarr;" :: T.Text)


            H.div ! A.class_ "clear" $ ""

viewSidebar :: SiteRender H.Html
viewSidebar = renderRawCopy "copy/static/home-links.md"
