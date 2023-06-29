{-# OPTIONS_GHC -Wno-missing-methods #-}

module FFI
  ( create,
    disposeMemory,
    checkLastError,
    processResponse,
    processRequest,
    load,
    setInigo,
    getInigo,
  )

where

import Data.IORef
import Foreign.Ptr
import System.Posix.DynamicLinker
import System.IO.Unsafe
import Foreign
import Foreign.C.Types
import Foreign.C.String
import Control.Monad

data Config = Config
  { debug                 :: Int8
  , ingest                :: CString
  , service               :: CString
  , token                 :: CString
  , schema                :: CString
  , introspection         :: CString
  , egressUrl             :: CString
  , gateway               :: WordPtr
  , disableResponseMerge  :: Int8
  } deriving (Show)

instance Storable Config where
    sizeOf _ = (sizeOf (undefined :: Int8)) * 2
             + (sizeOf (undefined :: CString)) * 6
             + (sizeOf (undefined :: WordPtr))
    alignment _ = alignment (undefined :: WordPtr)
    poke ptr (Config debug ingest service token schema introspection egressUrl gateway disableResponseMerge) = do
        pokeByteOff ptr 0 debug
        pokeByteOff ptr 8 ingest
        pokeByteOff ptr 16 service
        pokeByteOff ptr 24 token
        pokeByteOff ptr 32 schema
        pokeByteOff ptr 40 introspection
        pokeByteOff ptr 48 egressUrl
        pokeByteOff ptr 56 gateway
        pokeByteOff ptr 64 disableResponseMerge

load :: FilePath ->IO ()
load path = do
    loadCreate path
    loadCheckLastError path
    loadDisposeMemory path
    loadProcessResponse path
    loadProcessRequest path
    return ()

type Create = Ptr Config -> IO CSize

foreign import ccall "dynamic" cCreate :: FunPtr Create -> Create

createFn :: IORef Create
createFn = unsafePerformIO $ newIORef undefined

loadCreate :: FilePath -> IO Create
loadCreate libPath = do
    lib <- dlopen libPath [RTLD_NOW]
    funPtr <- dlsym lib "create"
    let fun = cCreate funPtr
    writeIORef createFn fun
    return fun

create :: String -> String -> CSize
create token egressUrl = unsafePerformIO $ do
    cToken <- newCString token
    cEgressUrl <- newCString egressUrl

    let config = Config 0 nullPtr nullPtr cToken nullPtr nullPtr cEgressUrl 0 0

    configPtr <- new config

    fn <- readIORef createFn
    fn configPtr

inigo :: IORef CSize
inigo = unsafePerformIO $ newIORef 0

setInigo :: CSize -> IO ()
setInigo val = writeIORef inigo val

getInigo :: IO CSize
getInigo = readIORef inigo

type DisposeMemory = Ptr () -> IO ()

foreign import ccall "dynamic" cDisposeMemory :: FunPtr DisposeMemory -> DisposeMemory

disposeMemoryFn :: IORef DisposeMemory
disposeMemoryFn = unsafePerformIO $ newIORef undefined

loadDisposeMemory :: FilePath -> IO DisposeMemory
loadDisposeMemory libPath = do
    lib <- dlopen libPath [RTLD_NOW]
    funPtr <- dlsym lib "disposeMemory"
    let fun = cDisposeMemory funPtr
    writeIORef disposeMemoryFn fun
    return fun

disposeMemory :: Ptr a -> IO ()
disposeMemory ptr = unsafePerformIO $ do
    fn <- readIORef disposeMemoryFn
    return $ fn (castPtr ptr)

type CheckLastError = IO CString

foreign import ccall "dynamic" cCheckLastError :: FunPtr CheckLastError -> CheckLastError

checkLastErrorFn :: IORef CheckLastError
checkLastErrorFn = unsafePerformIO $ newIORef undefined

loadCheckLastError :: FilePath -> IO CheckLastError
loadCheckLastError libPath = do
    lib <- dlopen libPath [RTLD_NOW]
    funPtr <- dlsym lib "check_lasterror"
    let fun = cCheckLastError funPtr
    writeIORef checkLastErrorFn fun
    return fun

checkLastError :: IO String
checkLastError = do
    fn <- readIORef checkLastErrorFn
    cErr <- fn
    err <- peekCString cErr
    return err


type ProcessResponse = CSize -> CSize -> CString -> CLLong -> Ptr CString -> Ptr CLLong -> IO ()

foreign import ccall "dynamic" cProcessResponse :: FunPtr ProcessResponse -> ProcessResponse

processResponseFn :: IORef ProcessResponse
processResponseFn = unsafePerformIO $ newIORef undefined

loadProcessResponse :: FilePath -> IO ProcessResponse
loadProcessResponse libPath = do
    lib <- dlopen libPath [RTLD_NOW]
    funPtr <- dlsym lib "process_response"
    let fun = cProcessResponse funPtr
    writeIORef processResponseFn fun
    return fun

processResponse :: CSize -> CSize -> CString -> CLLong -> IO [Char]
processResponse handlePtr reqHandle input input_len = do
  alloca $ \respPtr ->
    alloca $ \(respLenPtr :: Ptr CLLong) ->do
      poke respPtr nullPtr
      poke respLenPtr 0

      fn <- readIORef processResponseFn
      fn handlePtr reqHandle input input_len respPtr respLenPtr

      respLen <- peek respLenPtr
      respStr <- peek respPtr >>= peekCStringLen . (,fromIntegral respLen)

      when (respLen > 0) $ do
        pToDel <- peek respPtr
        disposeMemory pToDel

      return respStr

type ProcessRequest = CSize -> CString -> CLLong -> CString -> CLLong -> Ptr CString -> Ptr CLLong -> Ptr CString -> Ptr CLLong -> IO CSize

foreign import ccall "dynamic" cProcessRequest :: FunPtr ProcessRequest -> ProcessRequest

processRequestFn :: IORef ProcessRequest
processRequestFn = unsafePerformIO $ newIORef undefined

loadProcessRequest :: FilePath -> IO ProcessRequest
loadProcessRequest libPath = do
    lib <- dlopen libPath [RTLD_NOW]
    funPtr <- dlsym lib "process_request"
    let fun = cProcessRequest funPtr
    writeIORef processRequestFn fun
    return fun

processRequest :: CSize -> CString -> CLLong -> CString -> CLLong -> IO([Char], [Char], CSize)
processRequest handlePtr headers headersLen input input_len = do
  alloca $ \respPtr ->
    alloca $ \(respLenPtr :: Ptr CLLong) ->
    alloca $ \reqPtr ->
    alloca $ \(reqLenPtr :: Ptr CLLong) -> do
        poke respPtr nullPtr
        poke reqPtr nullPtr

        poke respLenPtr 0
        poke reqLenPtr 0

        fn <- readIORef processRequestFn
        rData <- fn handlePtr headers headersLen input input_len respPtr respLenPtr reqPtr reqLenPtr

        respLen <- peek respLenPtr
        respStr <- peek respPtr >>= peekCStringLen . (,fromIntegral respLen)

        when (respLen > 0) $ do
            peek respPtr >>= disposeMemory

        reqLen <- peek reqLenPtr
        reqStr <- peek reqPtr >>= peekCStringLen . (,fromIntegral reqLen)

        when (reqLen > 0) $ do
            peek reqPtr >>= disposeMemory

        return (respStr,reqStr,rData)
