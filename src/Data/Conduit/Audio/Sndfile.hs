{-# LANGUAGE LambdaCase #-}
module Data.Conduit.Audio.Sndfile where

import Data.Conduit.Audio
import qualified Data.Conduit as C
import qualified Data.Conduit.List as CL
import qualified Sound.File.Sndfile as Snd
import qualified Sound.File.Sndfile.Buffer.Vector as SndBuf
import Control.Monad.IO.Class
import Control.Monad (void)
import Control.Monad.Fix (fix)

sourceSnd :: (MonadIO m, MonadIO n) => FilePath -> Seconds -> m (AudioSource n)
sourceSnd fp posn = do
  info <- liftIO $ Snd.getFileInfo fp
  let r = Snd.samplerate info
      c = Snd.channels   info
      len = fromIntegral (Snd.frames info) / fromIntegral r
      chunkSize = 10000
      src = do
        h <- liftIO $ Snd.openFile fp Snd.ReadMode Snd.defaultInfo
        liftIO $ void $ Snd.hSeek h Snd.AbsoluteSeek $ round $ posn * fromIntegral r
        fix $ \loop -> liftIO (Snd.hGetBuffer h chunkSize) >>= \case
          Nothing  -> liftIO $ Snd.hClose h
          Just buf -> do
            SndBuf.fromBuffer buf `C.yieldOr` liftIO (Snd.hClose h)
            loop
  return $ AudioSource src r c $ max 0 $ len - posn

sinkSnd :: (MonadIO m) => FilePath -> Snd.Format -> AudioSource m -> m ()
sinkSnd fp fmt (AudioSource s r c _) = do
  h <- liftIO $ Snd.openFile fp Snd.WriteMode $ Snd.defaultInfo
    { Snd.format     = fmt
    , Snd.samplerate = r
    , Snd.channels   = c
    }
  s C.$$ CL.mapM_ (liftIO . void . Snd.hPutBuffer h . SndBuf.toBuffer)
  liftIO $ Snd.hClose h
