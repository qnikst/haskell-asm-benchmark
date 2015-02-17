module Main where

import qualified Data.ByteString.Lazy.Char8 as B

import Control.Monad (liftM, mapM_, forM_)
import Control.Monad.Trans.State.Strict
import Control.Monad.Trans

import System.IO

-- | Definitions

data Register = R1 | R2 | R3 | R4 | R5 | R6
                deriving (Show)
     
data Operator = ADD | SUB | MUL | DIV
              | LESS | EQUAL | AND | OR | NOT
              | MOV
              | JMT | JMF | JMP
              | PRN | NOP
                deriving (Show)

class OperandClass a where
   toOperand :: a -> Operand

instance OperandClass Register where
   toOperand = R

instance OperandClass Operand where
   toOperand = id

instance OperandClass () where
   toOperand _ = N

data Operand = R !Register | V !Double | I !Int | N
               deriving (Show)

type Instruction = (Operator, Operand, Operand) 


-- | Monad for programming instructions 

type ASM a = State [Instruction] a

compile :: ASM a -> [Instruction]
compile c = execState c []

op :: (OperandClass s, OperandClass d) => Operator -> s -> d -> ASM ()
op cmd src dst = modify $ \s -> s ++ [(cmd, toOperand src, toOperand dst)]

pos :: ASM Int
pos = liftM length $ get

nop :: ASM Int
nop = do { p <- pos; op NOP () (); return p}

putOp :: (OperandClass s, OperandClass d) => Int -> Operator -> s -> d -> ASM ()
putOp p cmd src dst = do
    let instr = (cmd, toOperand src, toOperand dst)
    (before,after) <- liftM (splitAt p) $ get 
    put $ before ++ instr:(tail after)

-- | Monad for executing instructions

data Registers = Registers
               { r1 :: !Double
               , r2 :: !Double
               , r3 :: !Double
               , r4 :: !Double
               , r5 :: !Double
               , r6 :: !Double
               } deriving (Show)

initialRs :: Registers
{-# INLINE initialRs #-}
initialRs = Registers
            { r1 = 0
            , r2 = 0
            , r3 = 0
            , r4 = 0
            , r5 = 0
            , r6 = 0
            }

type CPU a = StateT Registers IO a

execute ::Registers -> [Instruction] -> IO Registers
execute rs code = execStateT (exec code) rs
  where
   exec ((JMP, (I pos), _      ):is) = {-# SCC "JMP" #-} exec $ drop pos code
   exec ((JMF, reg,     (I pos)):is) = {-# SCC "JMF" #-} readVal reg >>= \v ->
                                                         exec $ if toBool v
                                                                then is
                                                                else drop pos code
   exec ((JMT, reg,     (I pos)):is) = {-# SCC "JMT" #-} readVal reg >>= \v ->
                                                         exec $ if toBool v
                                                                then drop pos code
                                                                else is
   exec ((ins, src,     dst    ):is) = {-# SCC "OP"  #-} execOP ins src dst >> exec is
   exec []                           = return ()

execOP :: Operator -> Operand -> Operand -> CPU ()
{-# INLINE execOP #-}
execOP ADD   src dst = {-# SCC "ADD"   #-} arith ADD   src dst
execOP SUB   src dst = {-# SCC "SUB"   #-} arith SUB   src dst
execOP MUL   src dst = {-# SCC "MUL"   #-} arith MUL   src dst
execOP DIV   src dst = {-# SCC "DIV"   #-} arith DIV   src dst
execOP LESS  src dst = {-# SCC "LESS"  #-} logic LESS  src dst
execOP EQUAL src dst = {-# SCC "EQUAL" #-} logic EQUAL src dst
execOP AND   src dst = {-# SCC "AND"   #-} logic AND   src dst
execOP OR    src dst = {-# SCC "OR"    #-} logic OR    src dst
execOP NOT   src dst = {-# SCC "NOT"   #-} logic NOT   src dst
execOP MOV   src dst = {-# SCC "MOV"   #-} readVal src >>= \v -> putVal v dst
execOP PRN   src _   = {-# SCC "PRN"   #-} readVal src >>= \v -> liftIO $ putStrLn $ show v 

arith :: Operator -> Operand -> Operand -> CPU ()
{-# INLINE arith #-}
arith op src dst = do
    v1 <- readVal src
    v2 <- readVal dst
    case op of
       ADD -> putVal (v2 + v1) dst
       SUB -> putVal (v2 - v1) dst
       MUL -> putVal (v2 * v1) dst
       DIV -> putVal (v2 / v1) dst

logic :: Operator -> Operand -> Operand -> CPU ()
{-# INLINE logic #-}
logic op src dst = do
     v1 <- readVal src
     v2 <- readVal dst
     case op of
        LESS  -> putVal (fromBool $ v2 <  v1) dst
        EQUAL -> putVal (fromBool $ v2 == v1) dst
        AND   -> putVal (fromBool $ toBool v1 && toBool v2) dst
        OR    -> putVal (fromBool $ toBool v1 && toBool v2) dst
        NOT   -> putVal (fromBool . not . toBool $ v1) dst

fromBool :: Bool -> Double
{-# INLINE fromBool #-}
fromBool True  = 1
fromBool False = 0

toBool :: Double -> Bool
{-# INLINE toBool #-}
toBool 0 = False
toBool _ = True

readVal :: Operand -> CPU Double
{-# INLINE readVal #-}
readVal (R R1) = gets r1
readVal (R R2) = gets r2
readVal (R R3) = gets r3
readVal (R R4) = gets r4
readVal (R R5) = gets r5
readVal (R R6) = gets r6
readVal (V v)  = return $ v

putVal :: Double -> Operand -> CPU ()
{-# INLINE putVal #-}
putVal v (R R1) = modify $ \s -> s { r1 = seq v v }
putVal v (R R2) = modify $ \s -> s { r2 = seq v v }
putVal v (R R3) = modify $ \s -> s { r3 = seq v v }
putVal v (R R4) = modify $ \s -> s { r4 = seq v v }
putVal v (R R5) = modify $ \s -> s { r5 = seq v v }
putVal v (R R6) = modify $ \s -> s { r6 = seq v v }


-- | Sample code

-- | Heron's method to calculate square root
-- Inputs:  r1 - value to calculate square root from
--          r2 - number of iterations
-- Outputs: r6 - output value
heron :: ASM ()
heron = do
   op MOV (V 1) R5
   op MOV (V 0) R3
   iterStart <- pos
   op MOV R3 R4
   op EQUAL R2 R4
   ifFalse <- nop
   op MOV R1 R6
   op DIV R5 R6
   op ADD R5 R6
   op MUL (V 0.5) R6
   op MOV R6 R5
   op ADD (V 1) R3
   op JMP (I iterStart) ()
   loopEnd <- pos
   putOp ifFalse JMT R4 (I loopEnd)
   op PRN R6 ()


-- | Test
main :: IO ()
main = do
  let h = compile heron
  input <- liftM (map (read . B.unpack) . B.words) $ B.hGetContents stdin
  forM_ input $ \i -> execute (initialRs {r1 = i, r2 = 10 }) h 
