{-# OPTIONS_GHC -Wno-deprecations #-}
{-# OPTIONS_GHC -Wno-missing-methods #-}

module Inigo
  ( inigoMiddleware,
  )

where

import Control.Applicative
import Data.ByteString qualified as B
import Prelude
import Network.Wai
import Data.ByteString.Builder (toLazyByteString)
import qualified Data.ByteString.Lazy.Char8 as L
import Network.HTTP.Types.Header
import Data.ByteString.Char8 (pack)
import qualified Data.ByteString.Lazy as BL
import Data.ByteString.Builder (byteString)
import Data.IORef
import Foreign
import Foreign.C.Types
import Foreign.C.String
import Data.List (deleteBy)
import Network.HTTP.Types
import Data.Aeson
import Control.Monad
import qualified Data.HashMap.Strict as HM
import Data.CaseInsensitive (mk)
import Data.ByteString.Char8 (pack)
import Foreign.Ptr
import System.Posix.DynamicLinker
import System.IO.Unsafe
import FFI



inigoMiddleware :: Middleware
inigoMiddleware app req respond = do
    inigo <- getInigo
    if rawPathInfo req /= pack "/v1/graphql" || ( (fromIntegral inigo :: Int) <= 0)
        then do
            err <- checkLastError
            when (length err > 0) $ do
                print err
            app req respond
        else do
            originalReqBody <- getRequestBody req

            let headers = L.unpack $ encode $ headersToMap $ requestHeaders req
            cHeaders <- newCString headers
            let reqHeadersLen = fromIntegral $ length headers

            let reqBody = L.unpack originalReqBody
            let reqBodyLen = fromIntegral $ length reqBody

            cReqBody <- newCString reqBody

            (goResp,goReq,goRData) <- processRequest inigo cHeaders reqHeadersLen cReqBody reqBodyLen

            free cReqBody

            if length goResp > 0
                then do
                    let response = responseLBS
                            status200  -- HTTP 200 OK
                            [(mk $ pack "Content-Type", pack "application/json")]
                            $ L.pack goResp  -- Response body
                    respond response
                else do
                    let newReqBody = if length goReq > 0
                        then goReq
                        else reqBody

                    bodyRef <- newIORef $ Just $ pack newReqBody
                    let newRequestBody = do
                            mBody <- readIORef bodyRef
                            case mBody of
                                Nothing -> return B.empty
                                Just body -> do
                                    writeIORef bodyRef Nothing
                                    return body

                    let newReq = req { requestBody = newRequestBody, requestHeaders = filter (\(name, _) -> name /= hAcceptEncoding) (requestHeaders req) }

                    app newReq $ \response -> do
                        body <- getResponseBody response

                        let respBody = L.unpack body
                        let respBodyLen = fromIntegral $ length respBody

                        cRespBody <- newCString respBody

                        newResp <- processResponse inigo goRData cRespBody respBodyLen

                        free cRespBody

                        let packedNewResp = L.pack newResp
                        let modifiedHeaders = setContentLength (responseHeaders response) $ fromIntegral $ length newResp
                        let modifiedResponse = responseLBS (responseStatus response) modifiedHeaders packedNewResp

                        respond modifiedResponse

headersToMap :: [Header] -> HM.HashMap String [String]
headersToMap headers = foldr insertHeader HM.empty headers
  where
    insertHeader (key, value) = HM.insertWith (++) (show key) [show value]

getRequestBody :: Request -> IO BL.ByteString
getRequestBody req = toLazyByteString . mconcat <$> loop where
    loop = do
        chunk <- getRequestBodyChunk req
        if B.null chunk
            then return []
            else do
                chunks <- loop
                return (byteString chunk : chunks)

setContentLength :: ResponseHeaders -> Int64 -> ResponseHeaders
setContentLength headers len =
  let withoutExisting = deleteBy (\(k, _) (k', _) -> k == k') (hContentLength, pack "") headers
  in (hContentLength, pack (show len)) : withoutExisting

getResponseBody :: Response -> IO L.ByteString
getResponseBody res =
  let  (_, _, body) = responseToStream res in
  body $ \f -> do
    content <- newIORef mempty
    f (\chunk -> modifyIORef' content (<> chunk)) (return ())
    toLazyByteString <$> readIORef content
